# bugsnag-roku
Bugsnag library for Roku

bugsnag-roku implements a Bugsnag error reporting client for Roku as a Task SceneGraph component which exposes an API hopefully familiar to user using Bugsnag in other programming languages.

There is currently no way to automatically handle all errors or collect user interaction data as breadcrumbs, so these actions are left to the library user to implement as they see fit.

## Getting started
1. [Create a Bugsnag account](https://www.bugsnag.com)
2. Crate a new project in Bugsnag. The type shouldn't matter much but TV makes the most sense.
3. Install bugsnag-roku in your project with `ropm install bugsnag-roku`
4. Instantiate the Bugsnag client as soon as possible, set the config fields on it and start the task:
```
	m.top.bugsnagTask = CreateObject("roSGNode", "bugsnagroku_BugsnagTask")
	m.top.bugsnagTask.setFields({
		"releaseStage": "prod",
		"appVersion": appVersion,
		"apiKey": BUGSNAG_API_KEY
	})
	m.top.bugsnagTask.control = "RUN"
```
5. Use the functions exposed on the Bugsnag task component to report events to Bugsnag.

Note: bugsnagroku_ is automatically added to all component and function names by ropm. At the moment, copying files into your project manually isn't supported out of the box because of ropm's partial prefixing. You would have to open all the source code files and remove all bugsnagroku_ prefixes.

## Configuration fields

| Field  | Default value | Description |
| ---------- | -------------- | --------------|
| releaseStage | "" | Release stage like production, prod, dev, development, stage, QA, test, etc. Can be any string.
| appVersion | "" | Version of the application that's using bugsnag-roku. If the version in the manifest is correct, this can be retreived from an instance of `roAppInfo`
| apiKey | "" | Your Bugsnag API key. Each project has a different API key.
| user | {} | Initial user data. This can be updated later using `bugsnagroku_updateUser()` function. If user ID is not set, the library may set it to device IP automatically (see below)
| reportChannelClientId | true | Whether to report channel client ID as part of device info. Client channel ID is unique per device/channel combination. It can uniquely identify a user within a Roku channel but not between multiple channels.
| useIpAsUserId | true | Whether to set user ID to device IP if it's not set in the initial user data.

## API reference

All functions are exposed on the instance of `bugsnagroku_BugsnagTask` component.

**bugsnagroku_notify(errorClass as String, errorMessage as String, severity as String, context as String, metaData as Object)**

Report an event to Bugsnag.

| Param  | Description |
| ---------- | -------------- |
| errorClass | Error class shown in Bugsnag UI. Since there is no automatic error handling in BrightScript, this can be any string. Something like "HttpError" or "ValidationError" is recommended since Bugsnag UI is designed to show error classes like that from other languages.
| errorMessage | Error message shown in Bugsnag UI. This should concisely describe what happened so that it can be easily both read and searched.
| severity | Event severity as defined by Bugsnag API. It can be `error`, `warning` or `info`. If an invalid value is supplied, the library will default to `error`.
| context | Location where the error happened. In web UIs this is the URL. Sicne Roku has no notion of a URL, this can be omitted, but it might be a good idea to send at least the name of the file where error occurred.
| metaData | {} | Metadata to attached to event.

**bugsnagroku_updateUser(userDiff as Object)**

Update user object sent with each event. The `userDiff` paremeter is an associative array mapping keys to update to their new values. In simple terms, any existing user associative array will be merged with the provided paramter.

**bugsnagroku_leaveBreadcrumb(name as String, breadcrumbType as String, metaData={})**

Add a new breadcrumb. All breadcrumbs are sent with every reported event.

| Param  | Description |
| ---------- | -------------- |
| name | Breadcrumb name shown in Bugsnag UI
| breadcrumbType | Breadcrumb type as defined by Busgnag API. May be `navigation`, `request`, `process`, `log`, `user`, `state`, `error`, `manual`. Unlike most other Bugsnag libraries, bugsnag-roku is unable to automatically detect any of those types of events.
| metaData | Metadata attached to the breadcrumb

## Contributing

Contributions are welcome. Before making a contribution, might be a good idea to make sure you're on the same wavelength as maintainers by opening an isuse and discussing whatever you want to fix, refactor or add to the library.

**Code Style**

* Flow control structures such as `if..else..end if`, `for..end for` and keywords such as `print`, `function`, `invalid`, etc should be all lowercase.
* All `function`, no `sub`
* System functions and variables should be PascalCase, for example `CreateObject()`, `ToStr()`, `GetScene()`, etc. Exceptions are `m` and `m.top`
* Library functions and variables should be camelCase, like `leaveBreadcrumb()` and `updateUser()`
* Use `REM` for important comments for visibility
* No `then` after `if` condition
* All HTTP requests are done on the task thread

**Commit Messages**

https://www.conventionalcommits.org/en/v1.0.0-beta.2/

No scope and no body preferred.

**Manual testing in your own app**

Install your version of the package by using relative path to it in your file system, for example `ropm install ../bugsnag-roku`.