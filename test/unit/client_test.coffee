chai = require("chai")
sinon = require("sinon")
sinon_chai = require("sinon-chai")
expect = chai.expect
chai.use(sinon_chai)

Client = require("../../src/client")


testWrap = (client) ->
  describe "wrap", ->
    it "does not invoke function immediately", ->
      fn = sinon.spy()
      client.wrap(fn)
      expect(fn).not.to.have.been.called

    it "creates wrapper that invokes function with passed args", ->
      fn = sinon.spy()
      wrapper = client.wrap(fn)
      wrapper("hello", "world")
      expect(fn).to.have.been.called
      expect(fn.lastCall.args).to.deep.equal(["hello", "world"])

    it "sets __airbrake__ and __inner__ properties", ->
      fn = sinon.spy()
      wrapper = client.wrap(fn)
      expect(wrapper.__airbrake__).to.equal(true)
      expect(wrapper.__inner__).to.equal(fn)

    it "copies function properties", ->
      fn = sinon.spy()
      fn.prop = "hello"
      wrapper = client.wrap(fn)
      expect(wrapper.prop).to.equal("hello")

    it "reports throwed exception", ->
      client.push = sinon.spy()
      exc = new Error("test")
      fn = ->
        throw exc
      wrapper = client.wrap(fn)
      wrapper("hello", "world")
      expect(client.push).to.have.been.called
      expect(client.push.lastCall.args).to.deep.equal([{error: exc, params: {arguments: ["hello", "world"]}}])

    it "wraps arguments", ->
      fn = sinon.spy()
      wrapper = client.wrap(fn)
      arg1 = ->
      wrapper(arg1)
      expect(fn).to.have.been.called
      arg1Wrapper = fn.lastCall.args[0]
      expect(arg1Wrapper.__airbrake__).to.equal(true)
      expect(arg1Wrapper.__inner__).to.equal(arg1)


describe "JS shim", ->
  testWrap(require("../../airbrake-shim.js").Airbrake)


describe "Coffee shim", ->
  testWrap(require("../../airbrake-shim.coffee").Airbrake)


describe "Client", ->
  clock = undefined
  beforeEach -> clock = sinon.useFakeTimers()
  afterEach -> clock.restore()

  writeThroughProcessor = null
  beforeEach -> writeThroughProcessor = (data, fn) -> fn('write-through', data)

  describe 'filters', ->
    processor    = null
    reporter     = null
    getProcessor = null
    getReporter  = null
    client       = null

    beforeEach ->
      processor      = sinon.spy()
      reporter       = sinon.spy()
      client         = new Client(processor, reporter)

    describe 'addFilter', ->
      it 'can prevent report', ->
        filter = sinon.spy((notice) -> false)
        client.addFilter(filter)

        client.push({})
        continueFromProcessor = processor.lastCall.args[1]
        continueFromProcessor('test', {})

        expect(reporter).not.to.have.been.called
        expect(filter).to.have.been.called

      it 'can allow report', ->
        filter = sinon.spy((notice) -> true)
        client.addFilter(filter)

        client.push(error: {})
        continueFromProcessor = processor.lastCall.args[1]
        continueFromProcessor('test', {})

        expect(reporter).to.have.been.called
        notice = reporter.lastCall.args[0]
        expect(filter).to.have.been.calledWith(notice)

  describe "push", ->
    exception = do ->
      error = undefined
      try
        (0)()
      catch _err
        error = _err
      return error

    describe "with error", ->
      it "processor is called", ->
        reporter = sinon.spy()
        processor = sinon.spy()

        client = new Client(processor, reporter)
        client.push(exception)

        expect(processor).to.have.been.called

      it "reporter is called with valid options", ->
        reporter = sinon.spy()
        processor = (err, cb) -> cb('', {})

        client = new Client(processor, reporter)
        client.setProject(999, "custom_project_key")
        client.push(exception)

        expect(reporter).to.have.been.called
        opts = reporter.lastCall.args[1]
        expect(opts).to.deep.equal({
          projectId: 999
          projectKey: "custom_project_key",
          host: "https://api.airbrake.io"
        })
      it "reporter is called with custom host", ->
        reporter = sinon.spy()

        client = new Client(writeThroughProcessor, reporter)
        client.setHost("https://custom.domain.com")
        client.push(exception)

        reported = reporter.lastCall.args[1]
        expect(reported.host).to.equal("https://custom.domain.com")

    describe "custom data sent to reporter", ->
      it "reports context", ->
        reporter = sinon.spy()

        client = new Client(writeThroughProcessor, reporter)
        client.addContext(context_key: "[custom_context]")
        client.push(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.context.context_key).to.equal("[custom_context]")

      it "reports environment name", ->
        reporter = sinon.spy()

        client = new Client(writeThroughProcessor, reporter)
        client.setEnvironmentName("[custom_env_name]")
        client.push(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.context.environment).to.equal("[custom_env_name]")

      it "reports environment", ->
        reporter = sinon.spy()

        client = new Client(writeThroughProcessor, reporter)
        client.addEnvironment(env_key: "[custom_env]")
        client.push(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.environment.env_key).to.equal("[custom_env]")

      it "reports params", ->
        reporter = sinon.spy()

        client = new Client(writeThroughProcessor, reporter)
        client.addParams(params_key: "[custom_params]")
        client.push(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.params.params_key).to.equal("[custom_params]")

      it "reports session", ->
        reporter = sinon.spy()

        client = new Client(writeThroughProcessor, reporter)
        client.addSession(session_key: "[custom_session]")
        client.push(exception)

        reported = reporter.lastCall.args[0]
        expect(reported.session.session_key).to.equal("[custom_session]")

      describe "wrapped error", ->
        it "unwraps and processes error", ->
          reporter = sinon.spy()
          processor = sinon.spy()

          client = new Client(processor, reporter)
          client.push(error: exception)
          expect(processor).to.have.been.calledWith(exception)

        it "reports custom context", ->
          reporter = sinon.spy()

          client = new Client(writeThroughProcessor, reporter)
          client.addContext(context1: "value1", context2: "value2")
          client.push
            error: exception
            context:
              context1: "push_value1"
              context3: "push_value3"

          reported = reporter.lastCall.args[0]
          expect(reported.context).to.deep.equal
            language: "JavaScript"
            sourceMapEnabled: true
            context1: "push_value1"
            context2: "value2"
            context3: "push_value3"

        it "reports custom environment name", ->
          reporter = sinon.spy()

          client = new Client(writeThroughProcessor, reporter)
          client.setEnvironmentName("env1")
          client.push
            error: exception
            context:
              environment: "push_env1"

          reported = reporter.lastCall.args[0]
          expect(reported.context).to.deep.equal
            language: "JavaScript"
            sourceMapEnabled: true
            environment: "push_env1"

        it "reports custom environment", ->
          reporter = sinon.spy()

          client = new Client(writeThroughProcessor, reporter)
          client.addEnvironment(env1: "value1", env2: "value2")
          client.push
            error: exception
            environment:
              env1: "push_value1"
              env3: "push_value3"

          reported = reporter.lastCall.args[0]
          expect(reported.environment).to.deep.equal
            env1: "push_value1"
            env2: "value2"
            env3: "push_value3"

        it "reports custom params", ->
          reporter = sinon.spy()

          client = new Client(writeThroughProcessor, reporter)
          client.addParams(param1: "value1", param2: "value2")
          client.push
            error: exception
            params:
              param1: "push_value1"
              param3: "push_value3"

          reported = reporter.lastCall.args[0]
          expect(reported.params).to.deep.equal
            param1: "push_value1"
            param2: "value2"
            param3: "push_value3"

        it "reports custom session", ->
          reporter = sinon.spy()

          client = new Client(writeThroughProcessor, reporter)
          client.addSession(session1: "value1", session2: "value2")
          client.push
            error: exception
            session:
              session1: "push_value1"
              session3: "push_value3"

          reported = reporter.lastCall.args[0]
          expect(reported.session).to.deep.equal
            session1: "push_value1"
            session2: "value2"
            session3: "push_value3"

  describe "data supplied by shim", ->
    it "reports processed error and options to custom reporter", ->
      custom_reporter = sinon.spy()
      processor = (err, cb) -> cb()
      client = new Client(processor, null)
      client.addReporter(custom_reporter)
      client.push(error: {})
      expect(custom_reporter).to.have.been.called

  testWrap(new Client())
