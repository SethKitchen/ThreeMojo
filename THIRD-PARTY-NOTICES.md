# Third-Party Notices

ThreeMojo incorporates or derives from the third-party software listed below.
These notices are reproduced as required by the respective licenses, and
nothing in ThreeMojo's own [LICENSE](LICENSE) limits any rights you hold in
this upstream software directly.

---

## three.js

<https://github.com/mrdoob/three.js>

ThreeMojo's `math/` and `render/` modules are a port of three.js to Mojo. The
class names, method semantics, and overall structure follow three.js; the Mojo
implementation is original work. three.js is distributed under the MIT License,
reproduced in full below.

Anyone may obtain three.js directly from its authors under the MIT License. The
noncommercial restriction in ThreeMojo's own license applies only to
ThreeMojo's code and has no effect whatsoever on your rights in three.js.

```
The MIT License

Copyright © 2010-2026 three.js authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

---

## Scope note

The `coverage/` directory — the line, branch, condition, and MC-DC coverage
tooling — is entirely original work with no three.js lineage. It is covered by
ThreeMojo's own license alone.

The Mojo toolchain and standard library are products of Modular Inc. and are
not redistributed by this project; they are installed separately by the user
under Modular's own terms.
