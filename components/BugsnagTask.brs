function init()
	m.notifier = {
		name: "Bugsnag Roku",
		url: "https://github.com/redboxllc/bugsnag-roku"
		version: "0.0.1"
	}

	m.top.id = "BugsnagTask"
	m.top.functionName = "bugsnagroku_startTask"

	if m.top.user = invalid
		m.user = {}
	else
		m.user = m.top.user
	end if

	if m.top.useIpAsUserId and m.user.id = invalid
		m.user.id = getDeviceInfo().GetExternalIp()
	end if

	' Create a Message Port'
	m.port = CreateObject("roMessagePort")
	m.top.ObserveField("request", m.port)
	m.top.ObserveField("deleteReqReference", m.port)

	m.jobs = {}
	m.top.reqRepo = {}

	loadedBreadcrumb = {
		name: "Bugsnag loaded",
		timestamp: getNowISO(),
		type: "navigation"
	}
	loadedBreadcrumb["metaData"] = {}
	m.breadcrumbs = [loadedBreadcrumb]

	m.severities = {
		error: true,
		warning: true,
		info: true,
	}

	m.top.ObserveField("response", "handleResponse")
end function

function updateUser(userDiff as object)
	if userDiff <> invalid
		for each diffKey in userDiff
			m.user[diffKey] = userDiff[diffKey]
		end for
	end if
end function

function leaveBreadcrumb(name as string, breadcrumbType as string, metaData = {})
	breadcrumb = {
		name: name,
		type: breadcrumbType,
		timestamp: getNowISO()
	}

	if metaData <> invalid
		breadcrumb["metaData"] = metaData
	end if

	m.breadcrumbs.Push(breadcrumb)
end function

function notify(errorClass as string, errorMessage as string, severity as string, context as string, metaData as object)
	data = {
		events: [],
		notifier: m.notifier
	}

	event = {
		app: createAppPayload(),
		breadcrumbs: m.breadcrumbs,
		device: createDevicePayload(),
		unhandled: false
	}

	if context <> invalid
		event["context"] = context
	end if

	exception = {
		message: errorMessage,
		stacktrace: []
	}
	exception["errorClass"] = errorClass
	event["exceptions"] = [exception]

	if (metadata <> invalid)
		event["metaData"] = metaData
	end if

	event["payloadVersion"] = "4"

	resolvedSeverity = "error"
	if (severity <> invalid and m.severities.doesExist(severity))
		resolvedSeverity = severity
	end if

	if (resolvedSeverity <> "info")
		m.session.events[severity] = m.session.events[severity] + 1
	end if

	event["session"] = m.session
	event["severity"] = resolvedSeverity
	event["severityReason"] = {
		type: "userSpecifiedSeverity"
	}

	if m.user <> invalid
		event["user"] = m.user
	end if

	data["events"] = [event]

	sendRequest({
		url: "https://notify.bugsnag.com",
		method: "POST",
		headers: {
			"bugsnag-api-key": m.top.apiKey,
			"bugsnag-payload-version": "4",
			"bugsnag-sent-at": getNowISO()
		},
		data: data,
		callback: bugsnagroku_handleSessionResponse
	})

	breadcrumbMetadata = {
		severity: severity
	}
	breadcrumbMetadata["errorClass"] = errorClass
	breadcrumbMetadata["errorMessage"] = errorMessage

	leaveBreadcrumb(errorClass, "error", breadcrumbMetadata)
end function

function createAppPayload()
	app = {
		version: m.top.appVersion
	}

	app["releaseStage"] = m.top.releaseStage

	return app
end function

function createDevicePayload()
	deviceInfo = getDeviceInfo()

	device = {
		locale: deviceInfo.GetCurrentLocale(),
		connection: deviceInfo.GetConnectionType(),
		model: deviceInfo.GetModel(),
		time: getNowISO(),
		tts: getAudioGuideStatusAsString()
	}

	if m.top.reportChannelClientId
		device["deviceId"] = deviceInfo.GetChannelClientId()
	end if

	device["firmwareVersion"] = deviceInfo.GetOSVersion()

	return device
end function

function getNowISO()
	now = CreateObject("roDateTime")
	return now.toISOString()
end function

function getAudioGuideStatusAsString()
	if (getDeviceInfo().IsAudioGuideEnabled())
		return "true"
	else
		return "false"
	end if
end function

function startSession()
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
	if m.user <> invalid
		session.user = m.user
	end if
	data.sessions.push(session)

	m.session = {
		id: session.id
	}
	m.session["startedAt"] = session.startedAt
	sessionEvents = {
		handled: 0
		unhandled: 0
	}
	m.session["events"] = sessionEvents

	sendRequest({
		url: "https://sessions.bugsnag.com",
		method: "POST",
		headers: {
			"bugsnag-api-key": m.top.apiKey,
			"bugsnag-payload-version": "1",
			"bugsnag-sent-at": now
		},
		data: data,
		callback: bugsnagroku_handleSessionResponse,
		jsonResponse: true
	})
end function

'***************
' startBugsnagTask:
' @desc Long running task to execute HTTP requests
'***************
function startTask()
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
		httpTransfer.SetHeaders(request.headers)
	end if
	httpTransfer.AddHeader("Content-Type", "application/json")

	httpTransfer.EnableEncodings(true)
	httpTransfer.RetainBodyOnError(true)
	httpTransfer.SetPort(m.port)
	httpTransfer.SetMessagePort(m.port)

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
		if m.top.logNetworkErrors
			logNetworkError(request, error)
		end if
	end if
end function

'***************
' @desc Handles HTTP Responses
' @param object roUrlEvent Object
'***************
function handleHTTPResponse(event)
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

			if bodyNotEmpty and job.request.jsonResponse <> invalid and job.request.jsonResponse
				data = parseJson(body)
			end if

			response = { error: false, code: code, data: data, request: job.request, msg: "" }
			m.top.response = createResponseModel(response, identity.ToStr())
		else
			error = { error: true, code: code, msg: event.GetFailureReason(), request: job.request, data: invalid }
			m.top.response = createResponseModel(error, identity.ToStr())
			if m.top.logNetworkErrors
				logNetworkError(request, error)
			end if
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
	m.top.request = req

	reqId = getDeviceInfo().GetRandomUUID()

	reqRepo = m.top.reqRepo
	reqRepo[reqId] = req
	m.top.reqRepo = reqRepo
end function

function handleSessionResponse(res)
	m.top.UnobserveFieldScoped("response")
end function

function handleResponse(res)
	if (res.callback)
		res.callback(res)
	end if
end function

function logNetworkError(request as object, error as object)
	print " **************************************** HTTP ERROR ****************************************** "
	print " ======================================== Request info ======================================== "
	print chr(10)

	if request <> invalid
		print " URL: "; request.url
		print " Query Params: "; request.queryParams
		print " Request Headers: " + chr(10)
		for each header in request.headers
			print " " + header + ": " + request.headers[header] + chr(10)
		end for
		print " Request Body: "; request.data
	end if

	print chr(10)
	print " ========================================   Response info ===================================== "
	print chr(10)

	print " Error code: ", error.code
	print " Failure Reason: "; error.msg

	print " ************************************************************************************************* "
end function