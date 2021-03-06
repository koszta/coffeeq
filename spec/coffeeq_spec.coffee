redis = require 'redis'
CoffeeQ = require '../lib/coffeeq'
Worker = CoffeeQ.Worker
redisClient = redis.createClient 6379, 'localhost'

describe 'A CoffeeQ client', ->
  client = null

  beforeEach (done) ->
    client = new CoffeeQ()
    redisClient.flushall done

  it 'checks that the coffeeq has a connection to redis', ->
    expect(client.queueClient).not.toBeNull()
    expect(client.pubsubClient).not.toBeNull()

  it 'adds an item to the queue and verifies one has been added', ->
    result = -1
    check = false
    qName = 'item1'

    # empty the test queue of items
    redisClient.ltrim client.activeKeyForQueue(qName), 1, 0, (err, res) =>
      # enqueue a new item
      client.enqueue qName, 'add', [1,4]
      redisClient.llen client.activeKeyForQueue(qName), (err, length) ->
        # set the current length
        check = true
        result = length

    waitsFor (-> check), "Redis operations didn't completed", 500
    runs -> expect(result).toEqual 1

  it 'adds multiple items to the queue and verifies the correct number have been added', ->
    result = -1
    check = false
    qName = 'item2'

    # empty the test queue of items
    redisClient.ltrim client.activeKeyForQueue(qName), 1, 0, (err, res) =>
      # enqueue a new item
      client.enqueue qName, 'add', [1,4]
      client.enqueue qName, 'add', [1,4]
      client.enqueue qName, 'add', [1,4]
      client.enqueue qName, 'add', [1,4]
      client.enqueue qName, 'add', [1,4]
      redisClient.llen client.activeKeyForQueue(qName), (err, length) ->
        # set the current length
        check = true
        result = length

    waitsFor (-> check), "Redis operations didn't completed", 500
    runs -> expect(result).toEqual 5

  it 'adds an item to the queue and verifies the correct item was added', ->
    result = -1
    check = false
    qName = 'item3'

    # empty the test queue of items
    redisClient.ltrim client.activeKeyForQueue(qName), 1, 0, (err, res) =>
      # enqueue a new item
      client.enqueue qName, 'multiply', [7,4]
      redisClient.lpop client.activeKeyForQueue(qName), (err, resp) ->
        # set the current length
        check = true
        result = resp

    waitsFor (-> check), "Redis operations didn't completed", 500
    runs ->
      resultObj = JSON.parse result
      expect(resultObj.class).toEqual 'multiply'
      expect(resultObj.args).toEqual [7,4]


describe 'A CoffeeQ Worker', ->
  client = null
  worker = null

  jobs =
    succeed: (callback) ->
      console.log
      console.log 'callback succeed'
      callback()
    fail: (callback) ->
      console.log 'callback fail'
      callback()
    multiply: (args...) ->
      callback a * b
    causeAnError: (a, callback) ->
      console.log "Running causeAnError #{a}"
      throw 'Exception in the wing wang!'
    waitForever: ->
      # no callback
    oneSec: (callback) ->
      setTimeout ->
        callback()
      , 1000

  # init the worker state for each test
  beforeEach (done) ->
    client = new CoffeeQ()
    worker = new Worker 'testing', jobs
    redisClient.flushall done

  afterEach ->
    worker.stop()

    # worker.on 'message', (worker, queue) ->
    #   console.log 'message fired'
    # worker.on 'job', (worker, queue) ->
    #   console.log 'job fired'
    # worker.on 'error', (worker, queue) ->
    #   console.log 'error fired'
    # worker.on 'success', (worker, queue, job, result) ->
    #   console.log "success fired with result #{result}"

  it 'checks that the worker has a connection to redis', ->
    expect(worker.queueClient).not.toBeNull()
    expect(worker.pubsubClient).not.toBeNull()

  it 'should process an item when one is added', (done) ->
    worker.on 'success', ->
      done()
    client.enqueue 'testing', 'succeed', []

  it 'should not process several jobs at once', (done) ->
    jobCount = 0
    worker.on 'success', ->
      done new Error 'this should not be called'
    worker.on 'job', ->
      jobCount++
      if jobCount > 1
        done new Error 'this should be called only once'
      else
        done()
    client.enqueue 'testing', 'waitForever', []
    client.enqueue 'testing', 'waitForever', []

  it 'should continue processing the second job', (done) ->
    successCount = 0
    worker.on 'success', ->
      successCount++
      done() if successCount == 2
    client.enqueue 'testing', 'oneSec', []
    client.enqueue 'testing', 'succeed', []

  describe 'with another worker', ->
    worker2 = null

    beforeEach ->
      worker2 = new Worker 'testing', jobs

    afterEach ->
      worker2.stop()

    it 'should spread the jobs', (done) ->
      workerDone = false
      worker2Done = false
      worker.on 'success', ->
        workerDone = true
        done() if workerDone && worker2Done
      worker2.on 'success', ->
        worker2Done = true
        done() if workerDone && worker2Done
      client.enqueue 'testing', 'oneSec', []
      client.enqueue 'testing', 'oneSec', []
