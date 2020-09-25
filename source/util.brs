function generateSessionId()
	chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	id = ""

	for i = 1 to 24
		id = id + chars.mid(rnd(36) - 1, 1)
	end for

	return id
end function