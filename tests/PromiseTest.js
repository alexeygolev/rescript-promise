// Generated by ReScript, PLEASE EDIT WITH CARE
'use strict';

var $$Promise = require("../src/Promise.js");

$$Promise.$$then($$Promise.$$then($$Promise.flatThen($$Promise.make(function (resolve, _reject) {
                  return resolve(1);
                }), (function (foo) {
                console.log(foo + 1 | 0);
                return $$Promise.resolve("This is working");
              })), (function (o) {
            console.log("Message received: " + o);
            return "test foo";
          })), (function (s) {
        console.log(s + " is a string");
        
      }));

var racer = $$Promise.$$then(Promise.race([
          $$Promise.resolve(3),
          $$Promise.resolve(2)
        ]), (function (r) {
        console.log("winner: ", r);
        
      }));

var foo = $$Promise.$$then($$Promise.make(function (param, reject) {
            return reject("oops");
          }).catch(function (e) {
          console.log(e);
          return 1;
        }), (function (num) {
        console.log("add + 1 to recovered", num + 1 | 0);
        
      }));

var interop = $$Promise.$$then($$Promise.$$then(Promise.resolve("interop promise"), (function (n) {
            console.log(n);
            return $$Promise.resolve("interop is working");
          })), (function (p) {
        return $$Promise.$$then(p, (function (msg) {
                      console.log(msg);
                      
                    }));
      }));

exports.racer = racer;
exports.foo = foo;
exports.interop = interop;
/*  Not a pure module */
