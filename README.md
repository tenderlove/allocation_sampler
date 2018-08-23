# allocation_sampler

* https://github.com/tenderlove/allocation_sampler

## DESCRIPTION:

A sampling allocation profiler.  This keeps track of allocations, but only on
specified intervals.  Useful for profiling allocations in programs where there
is a time limit on completion of the program.

## SYNOPSIS:

```ruby
as = ObjectSpace::AllocationSampler.new(interval: 1)
as.enable
10.times { Object.new }
as.disable

as.result # => {"Object"=>{"<compiled>"=>{1=>10}}}
```

## LICENSE:

(The MIT License)

Copyright (c) 2018 Aaron Patterson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
