function init(params as object) as object
	VERSION = "0.0.1"

	if params = invalid
		return invalid
	end if

	client = {}
	client.config = params

	now = CreateObject("roDateTime")
	nowISO = now.toISOString()

	deviceInfo = CreateObject("roDeviceInfo")

	data = {
		app: {},
		device: {},
		notifier: {},
		sessions: []
	}

	data.app["releaseStage"] = params.releaseStage
	data.app["version"] = params.appVersion

	data.device["locale"] = deviceInfo.GetCurrentLocale()

	data.notifier["name"] = "Bugsnag Roku"
	data.notifier["url"] = "https://github.com/redboxllc/bugsnag-roku"
	data.notifier["version"] = VERSION

	session = {}
	session["id"] = generateSessionId()
	session["startedAt"] = nowISO
	if params.user <> invalid
		session.user = params.user
	end if
	data.sessions.push(session)

	request({
		url: "https://sessions.bugsnag.com",
		method: "POST",
		headers: {
			"bugsnag-api-key": params.apiKey,
			"bugsnag-payload-version": 1
			"bugsnag-sent-at": nowISO
		},
		data: data
		onSuccess: handleSuccess
	})
end function

function handleSuccess(res)
	print "BUGSNAG REQ SUCCESS"
	print res
end function

function handleError(code, res)
	print "BUGSNAG REQ FAIL"
	print code
	print res
end function