# 

This repo is out of date. The current standard library no longer uses `@fieldParentPtr` interfaces for `Allocator` and `Random`, and basically uses what is proposed here.

#

The current "interface field" pattern in Zig has problems:

* It's too easy to shoot yourself by copying the interface out of its implementation: [#591](https://github.com/ziglang/zig/issues/591).
* It is unfriendly to the [optimizer](https://godbolt.org/z/WeS3c-).
* People don't like this pattern and find it hard to understand.

This repo is an alternative way of having userland interfaces and is designed around the idea that
the current interfaces are mostly used to get the helper functions they provide, and not the dynamic
dispatch. We, therefore, separate the two.

* A helper function is just a generic function that expects that the argument passed have certain
  functions that it can call (could have enhanched validation with [#1669](https://github.com/ziglang/zig/issues/1669)).
* When dynamic dispatch is needed, one can wrap their datastructure in a `struct {vtable: *c_void, impl: *c_void}`
  data structure and provide the same interface that the helper functions expect.

What do we gain from this?

* It's a lot harder to mess up your interface.
* When dynamic dispatch isn't used, the optimizer can better optimize your code ([release-small](https://godbolt.org/z/F2PSS-), [release-fast](https://godbolt.org/z/6XugKd), [release-safe](https://godbolt.org/z/pihtLc))
* Even when dynamic dispatch is used, the compiler still optimizes better ([release-small](https://godbolt.org/z/NpALLm), [release-fast](https://godbolt.org/z/WR4qHd), [release-safe](https://godbolt.org/z/HkhBGG))
