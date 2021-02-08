exception TestError(string)

let fail = msg => {
  Js.Exn.raiseError(msg)
}

let equal = (a, b) => {
  a == b
}

module Creation = {
  let resolveTest = () => {
    open Promise

    Promise.resolve("test")
    ->then(str => {
      Test.run(__POS_OF__("Should resolve test"), str, equal, "test")
      resolve()
    })
    ->ignore
  }

  let runTests = () => {
    resolveTest()
  }
}

module ThenChaining = {
  // A promise should be able to return a nested
  // Promise and also flatten it for another then call
  // to the actual value
  let testThen = () => {
    open Promise
    resolve(1)
    ->then(first => {
      resolve(first + 1)
    })
    ->then(value => {
      Test.run(__POS_OF__("Should be 2"), value, equal, 2)
      resolve()
    })
  }

  // It's not allowed to return a Promise.t<Promise.t<'a>> value
  // within a then. This operation will throw an error
  let testInvalidThen = () => {
    open Promise
    resolve(1)
    ->then(first => {
      resolve(resolve(first + 1))
    })
    ->then(p => {
      p
      ->then(value => {
        Test.run(__POS_OF__("Should be 2"), value, equal, 2)
        resolve()
      })
      ->ignore
      resolve()
    })
    ->catch(e => {
      let ret = switch e {
      | JsError(m) => Js.Exn.message(m) === Some("p.then is not a function")
      | _ => false
      }
      Test.run(__POS_OF__("then should have thrown an error"), ret, equal, true)
    })
  }

  let runTests = () => {
    testThen()->ignore
    testInvalidThen()->ignore
  }
}

module Rejection = {
  // Should gracefully handle a exn passed via reject()
  let testExnRejection = () => {
    let cond = "Expect rejection to contain a TestError"
    open Promise

    TestError("oops")
    ->reject
    ->catch(e => {
      Test.run(__POS_OF__(cond), e, equal, TestError("oops"))
    })
    ->ignore
  }

  let runTests = () => {
    testExnRejection()->ignore
  }
}

module Catching = {
  let asyncParseFail: unit => Js.Promise.t<string> = %raw(`
  function() {
    return new Promise((resolve) => {
      var result = JSON.parse("{..");
      return resolve(result);
    })
  }
  `)

  // Should correctly capture an JS error thrown within
  // a Promise `then` function
  let testExternalPromiseThrow = () => {
    open Promise

    asyncParseFail()
    ->then(_ => resolve()) // Since our asyncParse will fail anyways, we convert to Promise.t<unit> for our catch later
    ->catch(e => {
      let success = switch e {
      | JsError(err) => Js.Exn.message(err) == Some("Unexpected token . in JSON at position 1")
      | _ => false
      }

      Test.run(__POS_OF__("Should be a parser error with Unexpected token ."), success, equal, true)
    })
  }

  // Should correctly capture an exn thrown in a Promise
  // `then` function
  let testExnThrow = () => {
    open Promise

    resolve()
    ->then(_ => {
      raise(TestError("Thrown exn"))
    })
    ->catch(e => {
      let isTestErr = switch e {
      | TestError("Thrown exn") => true
      | _ => false
      }
      Test.run(__POS_OF__("Should be a TestError"), isTestErr, equal, true)
    })
  }

  // Should correctly capture a JS error raised with Js.Exn.raiseError
  // within a Promise then function
  let testRaiseErrorThrow = () => {
    open Promise

    let causeErr = () => {
      Js.Exn.raiseError("Some JS error")
    }

    resolve()
    ->then(_ => {
      causeErr()
    })
    ->catch(e => {
      let isTestErr = switch e {
      | JsError(err) => Js.Exn.message(err) == Some("Some JS error")
      | _ => false
      }
      Test.run(__POS_OF__("Should be some JS error"), isTestErr, equal, true)
    })
  }

  // Should recover a rejection and use then to
  // access the value
  let thenAfterCatch = () => {
    open Promise
    resolve()
    ->then(_ => {
      // NOTE: if then is used, there will be an uncaught
      // error
      reject(TestError("some rejected value"))
    })
    ->catch(e => {
      let s = switch e {
      | TestError("some rejected value") => "success"
      | _ => "not a test error"
      }
      s
    })
    ->then(msg => {
      Test.run(__POS_OF__("Should be success"), msg, equal, "success")
      resolve()
    })
  }

  let testCatchFinally = () => {
    open Promise
    let wasCalled = ref(false)
    resolve(5)
    ->then(_ => {
      reject(TestError("test"))
    })
    ->then(v => {
      v->resolve
    })
    ->catch(_ => {
      ()
    })
    ->finally(() => {
      wasCalled := true
    })
    ->then(v => {
      Test.run(__POS_OF__("value should be unit"), v, equal, ())
      Test.run(__POS_OF__("finally should have been called"), wasCalled.contents, equal, true)
      resolve()
    })
    ->ignore
  }

  let testResolveFinally = () => {
    open Promise
    let wasCalled = ref(false)
    resolve(5)
    ->then(v => {
      resolve(v + 5)
    })
    ->finally(() => {
      wasCalled := true
    })
    ->then(v => {
      Test.run(__POS_OF__("value should be 5"), v, equal, 10)
      Test.run(__POS_OF__("finally should have been called"), wasCalled.contents, equal, true)
      resolve()
    })
    ->ignore
  }

  let runTests = () => {
    testExternalPromiseThrow()->ignore
    testExnThrow()->ignore
    testRaiseErrorThrow()->ignore
    thenAfterCatch()->ignore
    testCatchFinally()->ignore
    testResolveFinally()->ignore
  }
}

module Concurrently = {
  let testParallel = () => {
    open Promise

    let place = ref(0)

    let delayedMsg = (ms, msg) => {
      Promise.make((resolve, _) => {
        Js.Global.setTimeout(() => {
          place := place.contents + 1
          resolve(.(place.contents, msg))
        }, ms)->ignore
      })
    }

    let p1 = delayedMsg(1000, "is Anna")
    let p2 = delayedMsg(500, "myName")
    let p3 = delayedMsg(100, "Hi")

    all([p1, p2, p3])->then(arr => {
      let exp = [(3, "is Anna"), (2, "myName"), (1, "Hi")]
      Test.run(__POS_OF__("Should have correct placing"), arr, equal, exp)
      resolve()
    })
  }

  let testRace = () => {
    open Promise

    let racer = (ms, name) => {
      Promise.make((resolve, _) => {
        Js.Global.setTimeout(() => {
          resolve(. name)
        }, ms)->ignore
      })
    }

    let promises = [racer(1000, "Turtle"), racer(500, "Hare"), racer(100, "Eagle")]

    race(promises)->then(winner => {
      Test.run(__POS_OF__("Eagle should win"), winner, equal, "Eagle")
      resolve()
    })
  }

  let runTests = () => {
    testParallel()->ignore
    testRace()->ignore
  }
}

Creation.runTests()
ThenChaining.runTests()
Rejection.runTests()
Catching.runTests()
Concurrently.runTests()
