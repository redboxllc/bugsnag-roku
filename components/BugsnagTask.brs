function init()
	m.top.id = "BugsnagTask"
	m.top.functionName = "startTask"

	m.port = CreateObject("roMessagePort")
	m.top.observeFieldScoped("notify", m.port)
	m.top.observeFieldScoped("leaveBreadcrumb", m.port)
	m.top.observeFieldScoped("updateUser", m.port)
end function

'***************
' startBugsnagTask:
' @desc Long running task to execute HTTP requests
'***************
function startTask()
	initDefaultValues()
	startSession()

	while (true)
		event = Wait(0, m.port)
		eventType = Type(event)
		if eventType = "roUrlEvent"
			handleHTTPResponse(event)
		else if eventType = "roSGNodeEvent"
			field = event.GetField()
			if field = "notify"
				eventData = event.GetData()
				notify(eventData)
			else if field = "leaveBreadcrumb"
				eventData = event.GetData()
				leaveBreadcrumb(eventData.name, eventData.breadcrumbType, eventData.metaData)
			else if field = "updateUser"
				eventData = event.GetData()
				updateUser(eventData)
			end if
		end if
	end while
end function

function initDefaultValues()
	m.notifier = {
		name: "Bugsnag Roku",
		url: "https://github.com/redboxllc/bugsnag-roku"
		version: "1.0.0"
	}

	if m.top.user = invalid
		m.user = {}
	else
		m.user = m.top.user
	end if

	if m.top.useIpAsUserId and m.user.id = invalid
		m.user.id = getDeviceInfo().GetExternalIp()
	end if

	m.jobs = {}
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

	session = {
		id: session.id
	}
	session["startedAt"] = session.startedAt
	sessionEvents = {
		handled: 0
		unhandled: 0
	}
	session["events"] = sessionEvents
	m.top.session = session

	sendRequest({
		url: "https://sessions.bugsnag.com",
		headers: {
			"bugsnag-api-key": m.top.apiKey,
			"bugsnag-payload-version": "1",
			"bugsnag-sent-at": now
		},
		data: data,
		jsonResponse: true
	})
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

' /**
'  * notify: Notifies the Bugsnag API that an error(s) has happened, and leaves an error breadcrumb
'  *
'  * @param {errorClass as string, errorMessage as string, severity as string, context as string, exceptions as object, metaData as object} errorInfo
'  * @return {Dynamic}
'  */
function notify(errorInfo as object)
	errorClass = errorInfo.errorClass
	errorMessage = errorInfo.errorMessage
	severity = errorInfo.severity
	context = errorInfo.context
	exceptions = errorInfo.exceptions
	metaData = errorInfo.metaData

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

	if exceptions <> invalid
		event["exceptions"] = exceptions
	else
		exception = {
			message: errorMessage,
			stacktrace: []
		}
		exception["errorClass"] = errorClass
		event["exceptions"] = [exception]
	end if

	if metaData <> invalid
		event["metaData"] = metaData
	end if

	event["payloadVersion"] = "4"

	resolvedSeverity = "error"
	if severity <> invalid and m.severities.DoesExist(severity)
		resolvedSeverity = severity
	end if

	if m.top.session <> invalid and m.top.session.events <> invalid
		' Only handled events are possible from brightscript so far
		session = m.top.session
		session.events.handled = session.events.handled + 1
		m.top.session = session
	end if

	event["session"] = m.top.session
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
		headers: {
			"bugsnag-api-key": m.top.apiKey,
			"bugsnag-payload-version": "4",
			"bugsnag-sent-at": getNowISO()
		},
		data: data
	})

	breadcrumbMetadata = { severity: severity }
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
	uiResolution = m.deviceInfo.GetUIResolution()

	device = {
		connection: deviceInfo.GetConnectionType(),
		generalMemoryLevel: deviceInfo.GetGeneralMemoryLevel(),
		locale: deviceInfo.GetCurrentLocale(),
		model: deviceInfo.GetModel(),
		time: getNowISO(),
		tts: getAudioGuideStatusAsString()
		uiResolution: uiResolution.height.ToStr() + "x" + uiResolution.width.ToStr()
	}

	if m.top.reportChannelClientId
		device["deviceId"] = deviceInfo.GetChannelClientId()
	end if

	if FindMemberFunction(deviceInfo, "GetOSVersion") <> invalid
		device["firmwareVersion"] = deviceInfo.GetOSVersion()
	else
		' Example version: 034.08E01185A
		version = deviceInfo.GetVersion()
		device["firmwareVersion"] = {
			major: Val(version.mid(2, 1)) ' From example, character 4
			minor: Val(version.mid(4, 1)) ' From example, character 0
			revision: Val(version.mid(5, 1)) ' From example, character 8
			build: Val(version.mid(8, 4)) ' From example, characters 1185
		}
	end if

	return device
end function

function getNowISO()
	now = CreateObject("roDateTime")
	return now.toISOString()
end function

function getAudioGuideStatusAsString()
	if getDeviceInfo().IsAudioGuideEnabled()
		return "true"
	else
		return "false"
	end if
end function

'***************
' @desc Handles HTTP requests (POST only)
' @param Object roSGNode event
'***************
function sendRequest(request as object) as void
	httpTransfer = CreateObject("roUrlTransfer")

	if httpTransfer = invalid
		' This can happen if for some reason the sendRequest is executed on the render thread.
		' Until we add some test coverage, maybe it's better to exit early and not send the err report than to crash the app
		print "[ERROR] [BugsnagRokuTask] roUrlTransfer is invalid. Request is not sent."
		return
	end if

	REM Add Roku cert for HTTPS requests
	if request.url.Left(6) = "https:"
		httpTransfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
		httpTransfer.AddHeader("X-Roku-Reserved-Dev-Id", "")
		httpTransfer.InitClientCertificates()
	end if

	requestBody = FormatJson(request.data)
	httpTransfer.SetUrl(request.url)

	if request.headers <> invalid
		httpTransfer.SetHeaders(request.headers)
	end if
	httpTransfer.AddHeader("Content-Type", "application/json")

	httpTransfer.EnableEncodings(true)
	httpTransfer.RetainBodyOnError(true)
	httpTransfer.SetPort(m.port)
	httpTransfer.SetMessagePort(m.port)

	success = httpTransfer.AsyncPostFromString(requestBody)

	if success
		identity = httpTransfer.GetIdentity()
		job = { httpTransfer: httpTransfer, request: request }
		m.jobs[identity.ToStr()] = job
	else
		error = { code: -10, msg: "Failed to create request for : " + request.url, request: request }
		if m.top.logNetworkErrors
			logNetworkError(error)
		end if
	end if
end function

'***************
' @desc Handles HTTP Responses
' @param object roUrlEvent Object
'***************
function handleHTTPResponse(event)
	transferComplete = (event.GetInt() = 1)

	if transferComplete
		identity = event.GetSourceIdentity()
		job = m.jobs.Lookup(identity.ToStr())

		if m.top.enableHttpLogs
			code = event.GetResponseCode()
			if (code >= 200) and (code < 300) and job <> invalid
				logNetworkResponse(event)
			else
				error = { code: code, msg: event.GetFailureReason(), request: job.request }
				logNetworkError(error)
			end if
		end if

		m.jobs.Delete(identity.toStr())
	end if
end function

function logNetworkError(error as object)
	request = error.request
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

function logNetworkResponse(roUrlEvt as object)
	print " **************************************** HTTP RESPONSE ****************************************** "
	print " ======================================== Response info ======================================== "
	print chr(10)
	if roUrlEvt <> invalid
		print " Response code: " + roUrlEvt.GetResponseCode() + chr(10)
		print " Response Body: "; roUrlEvt.GetString()
		print " Response Headers: " + chr(10)
		for each header in roUrlEvt.GetResponseHeadersArray()
			print " " + header + chr(10)
		end for
	end if
end function
