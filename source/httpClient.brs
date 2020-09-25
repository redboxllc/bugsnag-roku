function request(params as Object)
	req = CreateObject("roURLTransfer")

	REM resolve and set http method
	method = "GET"
	if (params.doesExist("method"))
		method = params.method
	end if

	if (method <> "GET" or method <> "POST")
		req.setRequest(method)
	end if

	isGetLikeRequest = method = "GET" or method = "DELETE"
	isPostLikeRequest = method = "POST" or method = "PUT" or method = "PATCH"

	REM resolve and set request data
	if (isGetLikeRequest)
		queryStringParts = []
		for each param in params.data
			queryStringParts.push(param + "=" + req.escape(params.data[param].toStr()))
		end for

		queryString = "?" + queryStringParts.join("&")
	else if (isPostLikeRequest)
		requestBody = FormatJson(params.data)
	end if

	REM build and set the url
	if (isGetLikeRequest)
		req.setUrl(params.url + queryString)
	else if (isPostLikeRequest)
		req.setUrl(params.url)
	end if

	REM set headers
	req.addHeader("Content-Type", "application/json")
	if (params.headeres <> invalid)
		req.setHeaders(params.headers)
	end if

 	REM create and set port for the response
	port = CreateObject("roMessagePort")
	req.setPort(port)
	req.retainBodyOnError(true)

	REM perform the request
	if (isGetLikeRequest)
		req.asyncGetToString()
	else if (isPostLikeRequest)
		req.asyncPostFromString(requestBody)
	end if

	while true
		msg = wait(100, port)

		if type(msg) = "roUrlEvent"
			statusCode = msg.getResponseCode()

			if (params.doesExist("onSuccess") and statusCode >= 200 and statucCode < 300)
				params.onSuccess(msg.getData())
			else if (params.doesExist("onError") and statusCode >= 400)
				params.onError(statusCode, msg.getData())
			end if

			exit while
		end if
	end while
end function
