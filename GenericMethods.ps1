#
# Test Code
#

Import-Module -Name .\PSGenericMethods.psm1 -Force

$cSharp = @'
    using System;
    using System.Management.Automation;
    using System.Collections.Generic;

    public class TestClass
    {
        public PSObject CreateObject<T> (string propertyName, T propertyValue)
        {
            PSObject o = new PSObject();
            o.Properties.Add(new PSNoteProperty(propertyName, propertyValue));

            return o;
        }

        public static PSObject StaticCreateObject<T> (string propertyName, T propertyValue)
        {
            PSObject o = new PSObject();
            o.Properties.Add(new PSNoteProperty(propertyName, propertyValue));

            return o;
        }

        public static TOut StaticCreateObject<TIn, TOut> (int? nullableTest, TIn ignore)
        {
            return default(TOut);
        }

        public static string DefaultParameterTest<T> (string required, string optional = "Default value")
        {
            return string.Format("'{0}', '{1}'", required, optional);
        }

        public static string GenericTypeParameterTest<T> (List<T> parameter)
        {
            return "GenericTypeParameterTest: " + parameter.ToString();
        }

        public static string GenericTypeParameterTest2<T> (List<string> parameter)
        {
            return "GenericTypeParameterTest: " + parameter.ToString();
        }

        public static string GenericTypeParameterTest3<T> (List<List<T>> parameter)
        {
            return "GenericTypeParameterTest: " + parameter.ToString();
        }

        public static string ArrayParameterTest<T>(T[] parameter)
        {
            if (parameter == null) { throw new ArgumentException("parameter"); }
            return parameter.GetType().FullName;
        }

        public static string OutParameterTest<T>(out T parameter, out string sparam)
        {
            parameter = default(T);
            sparam = "Out Value";
            return "OutParameterTest";
        }

        public static string RefParameterTest<T>(ref T parameter, ref string sparam)
        {
            string originalValue = sparam;

            parameter = default(T);
            sparam = "Out Value";
            return String.Format("RefParameterTest: '{0}'", originalValue); 
        }
    }
'@

Add-Type -TypeDefinition $cSharp

#cls

$VerbosePreference = 'Continue'

Write-Verbose "Testing Static Method"
Invoke-GenericMethod -Type TestClass -GenericType int -ArgumentList ('StaticTest', '12345') -MethodName StaticCreateObject | Out-Host

Write-Verbose 'Testing instance method'
$test = New-Object TestClass
$test | Invoke-GenericMethod -GenericType string -ArgumentList ('InstanceTest', 67890) -MethodName CreateObject | Out-Host

Write-Verbose "Testing Static Method 2"
Invoke-GenericMethod -Type TestClass -GenericType string,bool -ArgumentList ($null, 'Ignore') -MethodName StaticCreateObject | Out-Host

Write-Verbose "Testing method with default values (all arguments passed.)"
Invoke-GenericMethod -Type TestClass -GenericType string -ArgumentList ('Required Parameter', 'Optional Parameter') -MethodName DefaultParameterTest | Out-Host

Write-Verbose "Testing method with default values (optional parameter left to default)"
Invoke-GenericMethod -Type TestClass -GenericType string -ArgumentList ('Required Parameter') -MethodName DefaultParameterTest | Out-Host

Write-Verbose "Testing method with generic parameters"
$list = New-Object System.Collections.Generic.List[string]
$list.Add("This is a test.")
$list.Add("Line Two.")
Invoke-GenericMethod -Type TestClass -GenericType string -ArgumentList (,$list) -MethodName GenericTypeParameterTest | Out-Host

Write-Verbose "Testing method with generic array parameters"
[int[]] $array = 1,2,3,4,5
Invoke-GenericMethod -Type TestClass -MethodName ArrayParameterTest -GenericType int -ArgumentList (,$array)

Write-Verbose "Testing method with out parameters."
$int = 5
$string = "Before Method Call."
$args = ([ref]$int, [ref]$string)
Invoke-GenericMethod -Type TestClass -MethodName OutParameterTest -GenericType int -ArgumentList $args

Write-Host "int: '$int', string: '$string'"

Write-Verbose "Testing method with ref parameters."
$int = 5L
$string = "Before Method Call."
$args = ([ref]$int, [ref]$string)
Invoke-GenericMethod -Type TestClass -MethodName RefParameterTest -GenericType int -ArgumentList $args

Write-Host "int: '$int', string: '$string'"
