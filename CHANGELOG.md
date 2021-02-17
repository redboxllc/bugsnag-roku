# Changelog

All notable changes to this project will be documented in this file. See [standard-version](https://github.com/conventional-changelog/standard-version) for commit guidelines.

## [3.0.0](https://github.com/redboxllc/bugsnag-roku/compare/v2.0.0...v3.0.0) (2021-02-17)


### ⚠ BREAKING CHANGES

* - changed notify to be a filed instead of functional field, to prevent the client app from crashing as bugsnag_notify is using roUrlTransfer which might get executed on the render thread

### Bug Fixes

* move notify observer to the main Task loop ([2b21053](https://github.com/redboxllc/bugsnag-roku/commit/2b21053bfe4929229b4fc5311aa576ed05c344e8))


* trigger bugsnag notify via AA field, not via functional field ([f4d8050](https://github.com/redboxllc/bugsnag-roku/commit/f4d8050ee94d34113a13f4201ef031eeda909883))

## [2.0.0](https://github.com/redboxllc/bugsnag-roku/compare/v1.0.0...v2.0.0) (2021-01-19)


### ⚠ BREAKING CHANGES

* changed notify func signature

### Bug Fixes

* add guard agains invalid m.top.session ([5b4e109](https://github.com/redboxllc/bugsnag-roku/commit/5b4e109e678b5236356fe810d6db420dfe41254e))
* move standard-version to devDependencies ([728d4a2](https://github.com/redboxllc/bugsnag-roku/commit/728d4a233371b1ce68b466ae0ab3c8914f39a771))


* change notify func signature and implement handing for exceptions arr ([0f139db](https://github.com/redboxllc/bugsnag-roku/commit/0f139dbaa4aec745f3b5fe4b2eed74d9d1d7794d))
