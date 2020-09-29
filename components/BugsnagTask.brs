function init()
	print "BUGSNAG TASK INIT"

	m.VERSION = "0.0.1"

	m.top.id = "BugsnagTask"
	m.top.functionName = "bugsnag_startTask"

	' Create a Message Port'
	m.port = CreateObject("roMessagePort")
	m.top.ObserveField("request", m.port)
	m.top.ObserveField("deleteReqReference", m.port)

	m.jobs = {}
	m.top.reqRepo = {}

	m.deviceInfo = CreateObject("roDeviceInfo")
end function

function startSession()
	print "BUGSNAG START SESSION"

	now = CreateObject("roDateTime")
	nowISO = now.toISOString()

	m.deviceInfo = CreateObject("roDeviceInfo")

	data = {
		app: {},
		device: {},
		notifier: {},
		sessions: []
	}

	data.app["releaseStage"] = m.top.releaseStage
	data.app["version"] = m.top.appVersion

	data.device["locale"] = m.deviceInfo.GetCurrentLocale()

	data.notifier["name"] = "Bugsnag Roku"
	data.notifier["url"] = "https://github.com/redboxllc/bugsnag-roku"
	data.notifier["version"] = m.VERSION

	session = {}
	session["id"] = generateSessionId()
	session["startedAt"] = nowISO
	if m.top.user <> invalid
		session.user = m.top.user
	end if
	data.sessions.push(session)

	m.top.ObserveFieldScoped("response", "handleSessionResponse")

	sendRequest({
		url: "https://sessions.bugsnag.com",
		method: "POST",
		headers: {
			"bugsnag-api-key": m.top.apiKey,
			"bugsnag-payload-version": 1
			"bugsnag-sent-at": nowISO
		},
		data: data,
		onSuccess: handleSuccess
	})
end function

'***************
' startBugsnagTask:
' @desc Long running task to execute HTTP requests, transforms the responses to usable content nodes (models)
'***************
function startTask()
	print "BUGSNAG START TASK"

	while (true)
		event = Wait(0, m.port)
		eventType = Type(event)

		if (eventType = "roSGNodeEvent")
			eventField = event.GetField()

			if (eventField = "request")
					handleHTTPRequest(event)
			else if (eventField = "deleteReqReference")
				reqId = event.GetData()
				job = m.jobs.Lookup(reqId)
				m.jobs.Delete(reqId)
			end if
		else if (eventType = "roUrlEvent")
			handleHTTPResponse(event)
		end if
	end while
end function

'***************
' @desc Handles HTTP requests
' @param Object roSGNode event
'***************
function handleHTTPRequest(event)
	' Get the request data and fire
	request = event.GetData()

	httpTransfer = CreateObject("roUrlTransfer")

	' Add Roku cert for HTTPS requests
	if (request.url.Left(6) = "https:")
		httpTransfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
		httpTransfer.AddHeader("X-Roku-Reserved-Dev-Id", "")
		httpTransfer.InitClientCertificates()
	end if

	REM resolve and set http method
	method = "GET"
	if (request.DoesExist("method"))
		method = request.method
	end if
	if (method <> "GET" or method <> "POST")
		req.SetRequest(method)
	end if
	isGetLikeRequest = method = "GET" or method = "DELETE"
	isPostLikeRequest = method = "POST" or method = "PUT" or method = "PATCH"

	REM resolve and set request data
	if (isGetLikeRequest)
		queryStringParts = []
		for each param in request.data
			queryStringParts.Push(param + "=" + httpTransfer.Escape(params.data[param].ToStr()))
		end for

		queryString = "?" + queryStringParts.Join("&")
	else if (isPostLikeRequest)
		requestBody = FormatJson(request.data)
	end if

	REM build and set the url
	if (isGetLikeRequest)
		httpTransfer.SetUrl(request.url + queryString)
	else if (isPostLikeRequest)
		httpTransfer.SetUrl(request.url)
	end if

	REM set headers
	httpTransfer.AddHeader("Content-Type", "application/json")
	if (request.headeres <> invalid)
		httpTransfer.SetHeaders(request.headers)
	end if

	httpTransfer.EnableEncodings(true)
	httpTransfer.RetainBodyOnError(true)
	httpTransfer.SetPort(m.port)
	httpTransfer.SetMessagePort(m.port)

	REM perform the request
	if (isGetLikeRequest)
		success = req.AsyncGetToString()
	else if (isPostLikeRequest)
		success = req.AsyncPostFromString(requestBody)
	end if


	if (success)
		identity = httpTransfer.GetIdentity()

		job = { httpTransfer: httpTransfer, request: request }
		m.jobs[identity.ToStr()] = job
	else
		error = { error: true, code: -10, msg: "Failed to create request for : " + request.url, request: request, data: invalid }
		m.top.response = createResponseModel(error)
	 	' logNetworkError(request, error)
	end if
end function

'***************
' @desc Handles HTTP Responses
' @param object roUrlEvent Object
'***************
function handleHTTPResponse(event)
	' Get the data and send it back
	transferComplete = (event.GetInt() = 1)

	if (transferComplete)
		code = event.GetResponseCode()
		identity = event.GetSourceIdentity()
		job = m.jobs.Lookup(identity.ToStr())

		if ((code >= 200) and (code < 300) and job <> invalid)
			data = {}
			body = event.GetString()
			bodyNotEmpty = body <> invalid and body.Len() > 0

			if bodyNotEmpty
				data = parseJson(body)
			end if

			model = CreateObject("roSGNode", job.request.modelType)
			model.callFunc("parseData", data)

			' if IsValid(data) and IsValid(data.errors)
			' 	logNetworkError(job.request, event)
			' end if

			response = { error: false, code: code, data: model, request: job.request, msg: "" }
			m.top.response = createResponseModel(response, identity.ToStr())
		else
			error = { error: true, code: code, msg: event.GetFailureReason(), request: job.request, data: invalid }
			m.top.response = createResponseModel(error, identity.ToStr())
			' logNetworkError(job.request, event)
		end if
	end if
end function

'***************
' @desc Creates a response model
' @param Object
' @return Object ContentNode'
'***************
function createResponseModel(response as object, identityId = invalid) as object
	responseModel = CreateObject("roSGNode", "ResponseModel")
	responseModel.errorStatus = response.error
	responseModel.code = response.code
	responseModel.data = response.data
	responseModel.msg = response.msg
	responseModel.request = response.request

	if identityId <> invalid then responseModel.identityId = identityId

	return responseModel
end function

function sendRequest(req)
	m.top.request = requestQuery

	reqId = m.deviceInfo.GetRandomUUID()

	reqRepo = m.top.reqRepo
	reqRepo[reqId] = req
	m.top.reqRepo = reqRepo
end function

function handleSessionResponse(res)
	if res.error
		print "BUGSNAG REQ FAIL"
	else
		print "BUGSNAG REQ SUCCESS"
	end if

	print res

	m.top.UnobserveFieldScoped("response")
end function
