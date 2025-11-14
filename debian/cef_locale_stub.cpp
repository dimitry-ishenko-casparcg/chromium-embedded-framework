// Debian locale stub for protoc-gen-js linking
// Build 175: Pre-built library approach - Direct symbol definitions
//
// protoc-gen-js requires locale symbols from libc++ for iostream initialization,
// but the bundled libc++'s locale.cpp cannot be compiled on Debian due to
// type conflicts with glibc headers.
//
// This stub provides empty/minimal implementations of the required symbols.
// Compiled as a pre-built static library OUTSIDE the Chromium build system
// to bypass ThinLTO symbol stripping.

// Direct extern "C" linkage to provide the symbols without template complexity
extern "C" {
  // Provide basic symbols that protoc-gen-js needs for initialization
  // These are weak symbols that can be overridden if real locale is linked

  __attribute__((weak)) void _ZNSt4__Cr6localeD1Ev() {}
  __attribute__((weak)) void _ZNSt4__Cr6localeD2Ev() {}
  __attribute__((weak)) void _ZNSt4__Cr6locale9use_facetERNS0_2idE() {}
  __attribute__((weak)) void _ZNSt4__Cr7num_putIcNS_19ostreambuf_iteratorIcNS_11char_traitsIcEEEEED0Ev() {}
  __attribute__((weak)) void _ZNSt4__Cr7num_putIcNS_19ostreambuf_iteratorIcNS_11char_traitsIcEEEEED1Ev() {}
  __attribute__((weak)) void _ZNSt4__Cr7num_putIcNS_19ostreambuf_iteratorIcNS_11char_traitsIcEEEEED2Ev() {}
  __attribute__((weak)) void _ZNSt4__Cr7num_putIwNS_19ostreambuf_iteratorIwNS_11char_traitsIwEEEEED0Ev() {}
  __attribute__((weak)) void _ZNSt4__Cr7num_putIwNS_19ostreambuf_iteratorIwNS_11char_traitsIwEEEEED1Ev() {}
  __attribute__((weak)) void _ZNSt4__Cr7num_putIwNS_19ostreambuf_iteratorIwNS_11char_traitsIwEEEEED2Ev() {}
}
