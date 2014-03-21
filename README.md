PSGenericMethods
================

Tinkering with an Invoke-GenericMethod function to make calling generic methods on C# classes / objects easier.  After starting this, I realized that Lee Holmes did something similar years ago (http://www.leeholmes.com/blog/2007/06/19/invoking-generic-methods-on-non-generic-classes-in-powershell/ ), but it looks like he didn't go quite as far with it.

I've added code to handle $null arguments, and to perform some automatic type conversion, as we've come to expect from PowerShell (automatically converting numbers to Strings if needed, etc.)

Still thinking of ways to try to break the function (introducing Generic types as parameters, etc), but it seems like a good start.
