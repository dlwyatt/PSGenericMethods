PSGenericMethods
================

Tinkering with an Invoke-GenericMethod function to make calling generic methods on C# classes / objects easier.  After starting this, I realized that Lee Holmes did something similar years ago (http://www.leeholmes.com/blog/2007/06/19/invoking-generic-methods-on-non-generic-classes-in-powershell/ ), but it looks like he didn't go quite as far with it.

I've added code to handle $null arguments, and to perform some automatic type conversion, as we've come to expect from PowerShell (automatically converting numbers to Strings if needed, etc.)

So far, it seems to handle any combination of parameter / generic types that I can think to throw at it, but if you discover a way to make the function produce unexpected errors, please leave a report here and I'll get it taken care of.
