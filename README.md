# rescript-promise

This is a proposal for a better ReScript promise binding which aims to be as close to JS workflows as possible. It will be part of the official ReScript compiler if it proofs itself to be useful (aka. replacing the old `Js.Promise`).

> See the [PROPOSAL.md](./PROPOSAL.md) for the rationale and design decisions.

**Feature Overview:**

- `t-first` bindings
- Fully compatible with the builtin `Js.Promise.t` type
- `make` for creating a new promise with a `(resolve, reject) => {}` callback
- `resolve` for creating a resolved promise with an arbitrary value
- `reject` for creating a rejected promise
- `map` for transforming values within a promise chain
- `catch` for catching any JS or ReScript errors (all represented as an `exn` value)
- `then` for chaining functions that return another promise
- `all` and `race` for running promises concurrently
- `finally` for arbitrary tasks after a promise has rejected / resolved
- Globally accessible `Promise` module that doesn't collide with `Js.Promise`

**Non-Goals of `rescript-promise`:**

- No rejection tracking or other complex type hackery
- No special utilities (we will add docs on how to implement common utils on your own)

**Caveats:**

- There are 2 edge-cases where returning a `Promise.t<Promise.t<'a>>` value within `then` / `map` is not runtime safe (but also quite nonsensical). Refer to the [Common Mistakes](#common-mistakes) section for details.
- These edge-cases shouldn't happen in day to day use, also, for those who have general concerns of runtime safetiness, should use a `catch` call in the end of each promise chain anyways

## Requirements

`bs-platform@8.2` and above.

## Installation

```
npm install @ryyppy/rescript-promise --save
```

Add `@ryyppy/rescript-promise` as a dependency in your `bsconfig.json`:

```json
{
  "bs-dependencies": ["@ryyppy/rescript-promise"]
}
```

This will expose a global `Promise` module (don't worry, it will not mess with your existing `Js.Promise` code).

## Examples

- [examples/FetchExample.res](examples/FetchExample.res): Using the `fetch` api to login / query some data with a full promise chain scenario

## Usage

**Creating a Promise:**

```rescript
let p1 = Promise.make((resolve, _reject) => {
  resolve(. "hello world")
})

let p2 = Promise.resolve("some value")

// You can only reject `exn` values for streamlined catch handling
exception MyOwnError(string)
let p3 = Promise.reject(MyOwnError("some rejection"))
```

**Access and transform a promise value:**

```rescript
open Promise
Promise.resolve("hello world")
->map(msg => {
  // `map` allows the transformation of a nested promise value
  Js.log("Message: " ++ msg)
})
->ignore // Requires ignoring due to unhandled return value
```

**Chain promises:**

```rescript
type user = {"name": string}
type comment = string
@val external queryComments: string => Js.Promise.t<array<comment>> = "API.queryComments"
@val external queryUser: string => Js.Promise.t<user> = "API.queryUser"

open Promise

queryUser("patrick")
->then(user => {
  // We use `then` instead of `map` to automatically
  // unnest our queryComments promise
  queryComments(user["name"])
})
->map(comments => {
  // comments is now an array<comment>
  Belt.Array.forEach(comments, comment => Js.log(comment))
})
->ignore
```

**Catch promise errors:**

**Important:** `catch` needs to return the same return value as its previous `then` / `map` call (e.g. if you pass a `promise` of type `Promise.t<int>`, you need to return an `int` in your `catch` callback).

```rescript
exception MyError(string)

open Promise

Promise.reject(MyError("test"))
->map(str => {
  Js.log("this should not be reached: " ++ str)
  Ok("successful")
})
->catch(e => {
  let err = switch e {
  | MyError(str) => "found MyError: " ++ str
  | _ => "Some unknown error"
  }
  Error(err)
})
->map(result => {
  let msg = switch result {
  | Ok(str) => "Successful: " ++ str
  | Error(msg) => "Error: " ++ msg
  }
  Js.log(msg)
})
->ignore
```

**Catch promise errors caused by a thrown JS exception:**

```rescript
open Promise

let causeErr = () => {
  Js.Exn.raiseError("Some JS error")
}

Promise.resolve()
->map(_ => {
  causeErr()
})
->catch(e => {
  switch e {
  | JsError(obj) =>
    switch Js.Exn.message(obj) {
    | Some(msg) => Js.log("Some JS error msg: " ++ msg)
    | None => Js.log("Must be some non-error value")
    }
  | _ => Js.log("Some unknown error")
  }
})
->ignore
```

**Catch promise errors that can be caused by ReScript OR JS Errors (mixed error types):**

Every value passed to `catch` are unified into an `exn` value, no matter if those errors were thrown in JS, or in ReScript. This is similar to how we [handle mixed JS / ReScript errors](https://rescript-lang.org/docs/manual/latest/exception#catch-both-rescript-and-js-exceptions-in-the-same-catch-clause) in synchronous try / catch blocks.

```rescript
exception TestError(string)

let causeJsErr = () => {
  Js.Exn.raiseError("Some JS error")
}

let causeReScriptErr = () => {
  raise(TestError("Some ReScript error"))
}

// imaginary randomizer function
@bs.val external generateRandomInt: unit => int = "generateRandomInt"

open Promise

resolve()
->map(_ => {
  // We simulate a promise that either throws
  // a ReScript error, or JS error
  if generateRandomInt() > 5 {
    causeReScriptErr()
  } else {
    causeJsErr()
  }
})
->catch(e => {
  switch e {
  | TestError(msg) => Js.log("ReScript Error caught:" ++ msg)
  | JsError(obj) =>
    switch Js.Exn.message(obj) {
    | Some(msg) => Js.log("Some JS error msg: " ++ msg)
    | None => Js.log("Must be some non-error value")
    }
  | _ => Js.log("Some unknown error")
  }
})
->ignore
```

**Using a promise from JS:**

```rescript
@val external someAsyncApi: unit => Js.Promise.t<string> = "someAsyncApi"

someAsyncApi()->Promise.map((str) => Js.log(str))->ignore
```

**Running multiple Promises concurrently:**

```rescript
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

all([p1, p2, p3])->map(arr => {
  // [ [ 3, 'is Anna' ], [ 2, 'myName' ], [ 1, 'Hi' ] ]
  Belt.Array.map(arr, ((place, name)) => {
    Js.log(`Place ${Belt.Int.toString(place)} => ${name}`)
  })
  // Output
  // Place 3 => is Anna
  // Place 2 => myName
  // Place 1 => Hi
})
->ignore
```

**Race Promises:**

```rescript
open Promise

let racer = (ms, name) => {
  Promise.make((resolve, _) => {
    Js.Global.setTimeout(() => {
      resolve(. name)
    }, ms)->ignore
  })
}

let promises = [racer(1000, "Turtle"), racer(500, "Hare"), racer(100, "Eagle")]

race(promises)
->map(winner => {
  Js.log("Congrats: " ++ winner)
  // Congrats: Eagle
})
->ignore
```

## Common Mistakes

**Don't return a `Promise.t<'a>` within a `map` callback:**

```rescript
open Promise

resolve(1) ->map((value: int) => {

    // BAD: This will cause a Promise.t<Promise.t<'a>>
    resolve(value)
  })
  ->map((p: Promise.t<int>) => {
    // p is marked as a Promise, but it's actually an int
    // so this code will fail
    p->map((n) => Js.log(n))->ignore
  })
  ->catch((e) => {
    Js.log("luckily, our mistake will be caught here");
    // e: p.then is not a function
  })
  ->ignore
```

**Don't return a `Promise.t<Promise.t<'a>>` within a `then` callback:**

```rescript
open Promise

resolve(1)
  ->then((value: int) => {
    let someOtherPromise = resolve(2)

    // BAD: this will cause a Promise.t<Promise.t<'a>>
    resolve(someOtherPromise)
  })
  ->map((p: Promise.t<int>) => {
    // p is marked as a Promise, but it's actually an int
    // so this code will fail
    p->map((n) => Js.log(n))->ignore
  })
  ->catch((e) => {
    Js.log("luckily, our mistake will be caught here");
    // e: p.then is not a function
  })
  ->ignore
```

## Development

```
# Building
npm run build

# Watching
npm run dev
```

## Run Test

Runs all tests

```
node tests/PromiseTest.js
```

## Run Examples

Examples are runnable on node, and require an active internet connection to be able to access external mockup apis.

```
node examples/FetchExample.js
```
