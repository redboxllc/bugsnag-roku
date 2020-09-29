function init()
	print "BUGSNAG TASK INIT"

	m.notifier = {
		name: "Bugsnag Roku",
		url: "https://github.com/redboxllc/bugsnag-roku"
		version: "0.0.1"
	}

	m.top.id = "BugsnagTask"
	m.top.functionName = "bugsnagroku_startTask"

	' Create a Message Port'
	m.port = CreateObject("roMessagePort")
	m.top.ObserveField("request", m.port)
	m.top.ObserveField("deleteReqReference", m.port)

	m.jobs = {}
	m.top.reqRepo = {}

	m.deviceInfo = CreateObject("roDeviceInfo")
	m.breadcrumbs = []
end function

function notify()
	print "BUGSNAG NOTIFY"

	data = {
		events: [],
		notgifier: m.notifier
	}

	data["apiKey"] = m.top.apiKey

	event = {
		app: createAppPayload(),
		breadcrumbs: m.breadcrumbs,
		device: createDevicePayload()
	}
end function

function createAppPayload()
	app = {
		version: m.top.appVersion
	}

	app["releaseStage"] = m.top.releaseStage

	return app
end function

function createDevicePayload()
	device = {
		locale: m.deviceInfo.GetCurrentLocale(),
		connection: m.deviceInfo.GetConnectionType(),
		model: m.deviceInfo.GetModel(),
		time: getNowISO(),
		tts: getAudioGuideStatusAsString()
	}

	if m.top.reportChannelClientId
		device["deviceId"] = m.deviceInfo.GetChannelClientId()
	end if

	device["firmwareVersion"] = m.deviceInfo.GetOSVersion()

	return device
end function

function getNowISO()
	now = CreateObject("roDateTime")
	return now.toISOString()
end function

function getAudioGuideStatusAsString()
	if (m.deviceInfo.IsAudioGuideEnabled())
		return "true"
	else
		return "false"
	end if
end function

function startSession()
	print "BUGSNAG START SESSION"

	data = {
		app: createAppPayload(),
		device: createDevicePayload(),
		notifier: m.notifier,
		sessions: []
	}

	now = getNowISO()

	session = {}
	session["id"] = generateSessionId()
	session["startedAt"] = now
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
			"bugsnag-payload-version": "1",
			"bugsnag-sent-at": now
		},
		data: data
	})
end function

'***************
' startBugsnagTask:
' @desc Long running task to execute HTTP requests, transforms the responses to usable content nodes (models)
'***************
function startTask()
	print "BUGSNAG START TASK"

	startSession()

	while (true)
		event = Wait(0, m.port)
		eventType = Type(event)

		if eventType = "roSGNodeEvent"
			eventField = event.GetField()

			if eventField = "request"
					handleHTTPRequest(event)
			else if eventField = "deleteReqReference"
				reqId = event.GetData()
				job = m.jobs.Lookup(reqId)
				m.jobs.Delete(reqId)
			end if
		else if eventType = "roUrlEvent"
			handleHTTPResponse(event)
		end if
	end while
end function

'***************
' @desc Handles HTTP requests
' @param Object roSGNode event
'***************
function handleHTTPRequest(event)
	print "BUGSNAG HANDLE REQUEST"

	' Get the request data and fire
	request = event.GetData()

	httpTransfer = CreateObject("roUrlTransfer")

	' Add Roku cert for HTTPS requests
	if request.url.Left(6) = "https:"
		httpTransfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
		httpTransfer.AddHeader("X-Roku-Reserved-Dev-Id", "")
		httpTransfer.InitClientCertificates()
	end if

	REM resolve and set http method
	method = "GET"
	if request.DoesExist("method")
		method = request.method
	end if
	if method <> "GET" or method <> "POST"
		httpTransfer.SetRequest(method)
	end if
	isGetLikeRequest = method = "GET" or method = "DELETE"
	isPostLikeRequest = method = "POST" or method = "PUT" or method = "PATCH"

	REM resolve and set request data
	if isGetLikeRequest
		queryStringParts = []
		for each param in request.data
			queryStringParts.Push(param + "=" + httpTransfer.Escape(params.data[param].ToStr()))
		end for

		queryString = "?" + queryStringParts.Join("&")
	else if isPostLikeRequest
		requestBody = FormatJson(request.data)
	end if

	REM build and set the url
	if isGetLikeRequest
		httpTransfer.SetUrl(request.url + queryString)
	else if isPostLikeRequest
		httpTransfer.SetUrl(request.url)
	end if

	REM set headers
	if request.headers <> invalid
		print "BUGSNAG SET HEADERS"
		print request.headers
		httpTransfer.SetHeaders(request.headers)
	end if
	httpTransfer.AddHeader("Content-Type", "application/json")

	httpTransfer.EnableEncodings(true)
	httpTransfer.RetainBodyOnError(true)
	httpTransfer.SetPort(m.port)
	httpTransfer.SetMessagePort(m.port)

	print "REQUEST URL " + request.url
	if requestBody <> invalid
		print "REQUEST BODY " + requestBody
	end if
	if request.headers <> invalid
		print "REQEST HEADERS"
		print request.headers
	end if

	REM perform the request
	if isGetLikeRequest
		success = httpTransfer.AsyncGetToString()
	else if isPostLikeRequest
		success = httpTransfer.AsyncPostFromString(requestBody)
	end if


	if success
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
	print "BUGSNAG HANDLE RESPONSE"

	' Get the data and send it back
	transferComplete = (event.GetInt() = 1)

	if transferComplete
		code = event.GetResponseCode()
		identity = event.GetSourceIdentity()
		job = m.jobs.Lookup(identity.ToStr())

		if (code >= 200) and (code < 300) and job <> invalid
			data = {}
			body = event.GetString()
			bodyNotEmpty = body <> invalid and body.Len() > 0

			if bodyNotEmpty
				data = parseJson(body)
			end if

			print "BUGSNAG RESPONSE SUCCESS"
			print body

			response = { error: false, code: code, data: data, request: job.request, msg: "" }
			m.top.response = createResponseModel(response, identity.ToStr())
		else
			print "BUGSNAG RESPONSE FAILURE"
			print code
			print event.GetFailureReason()
			print event.GetString()

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
	print "BUGSNAG SEND REQUEST"
	print req

	m.top.request = req

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
