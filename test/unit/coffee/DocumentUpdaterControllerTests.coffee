SandboxedModule = require('sandboxed-module')
sinon = require('sinon')
require('chai').should()
modulePath = require('path').join __dirname, '../../../app/js/DocumentUpdaterController'
MockClient = require "./helpers/MockClient"

describe "DocumentUpdaterController", ->
	beforeEach ->
		@project_id = "project-id-123"
		@doc_id = "doc-id-123"
		@callback = sinon.stub()
		@io = { "mock": "socket.io" }
		@EditorUpdatesController = SandboxedModule.require modulePath, requires:
			"logger-sharelatex": @logger = { error: sinon.stub(), log: sinon.stub() }
			"settings-sharelatex": @settings =
				redis: web: {}
			"redis-sharelatex" : 
				createClient: ()=> 
					@rclient = {auth:->}

	describe "listenForUpdatesFromDocumentUpdater", ->
		beforeEach ->
			@rclient.subscribe = sinon.stub()
			@rclient.on = sinon.stub()
			@EditorUpdatesController.listenForUpdatesFromDocumentUpdater()
		
		it "should subscribe to the doc-updater stream", ->
			@rclient.subscribe.calledWith("applied-ops").should.equal true

		it "should register a callback to handle updates", ->
			@rclient.on.calledWith("message").should.equal true

	describe "_processMessageFromDocumentUpdater", ->
		describe "with update", ->
			beforeEach ->
				@message =
					doc_id: @doc_id
					op: {t: "foo", p: 12}
				@EditorUpdatesController._applyUpdateFromDocumentUpdater = sinon.stub()
				@EditorUpdatesController._processMessageFromDocumentUpdater @io, "applied-ops", JSON.stringify(@message)

			it "should apply the update", ->
				@EditorUpdatesController._applyUpdateFromDocumentUpdater
					.calledWith(@io, @doc_id, @message.op)
					.should.equal true

		describe "with error", ->
			beforeEach ->
				@message =
					doc_id: @doc_id
					error: "Something went wrong"
				@EditorUpdatesController._processErrorFromDocumentUpdater = sinon.stub()
				@EditorUpdatesController._processMessageFromDocumentUpdater @io, "applied-ops", JSON.stringify(@message)

			it "should process the error", ->
				@EditorUpdatesController._processErrorFromDocumentUpdater
					.calledWith(@io, @doc_id, @message.error)
					.should.equal true

	describe "_applyUpdateFromDocumentUpdater", ->
		beforeEach ->
			@sourceClient = new MockClient()
			@otherClients = [new MockClient(), new MockClient()]
			@update =
				op: [ t: "foo", p: 12 ]
				meta: source: @sourceClient.id
				v: @version = 42
				doc: @doc_id
			@io.sockets =
				clients: sinon.stub().returns([@sourceClient, @otherClients...])
			@EditorUpdatesController._applyUpdateFromDocumentUpdater @io, @doc_id, @update

		it "should send a version bump to the source client", ->
			@sourceClient.emit
				.calledWith("otUpdateApplied", v: @version, doc: @doc_id)
				.should.equal true

		it "should get the clients connected to the document", ->
			@io.sockets.clients
				.calledWith(@doc_id)
				.should.equal true

		it "should send the full update to the other clients", ->
			for client in @otherClients
				client.emit
					.calledWith("otUpdateApplied", @update)
					.should.equal true

	describe "_processErrorFromDocumentUpdater", ->
		beforeEach ->
			@clients = [new MockClient(), new MockClient()]
			@io.sockets =
				clients: sinon.stub().returns(@clients)
			@EditorUpdatesController._processErrorFromDocumentUpdater @io, @doc_id, "Something went wrong"

		it "should log out an error", ->
			@logger.error.called.should.equal true

		it "should disconnect all clients in that document", ->
			@io.sockets.clients.calledWith(@doc_id).should.equal true
			for client in @clients
				client.disconnect.called.should.equal true

