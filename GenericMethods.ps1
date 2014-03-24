#
# Test Code
#

Import-Module -Name .\PSGenericMethods.psm1 -Force

$cSharp = @'
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

        public static string NonGenericTest(List<string> list)
        {
            if (null == list) { return string.Empty; }

            return string.Join("\r\n", list.ToArray());
        }
    }
'@

Add-Type -TypeDefinition $cSharp

cls

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

Write-Verbose "Testing non-generic method with generic parameters"

# Verifying that the exception we're getting from Invoke when the method has a generic type argument is not caused by Invoke-GenericMethod specific code,
# but affects all calls to methods with signatures like this.  Still need to figure out if there's a way to fix this.  Possibly by rewriting the Invoke-GenericMethod
# function as a C# cmdlet (which would perform better anyway.)

$method = [TestClass].GetMethod('NonGenericTest')
$method.Invoke($null, (,$list))
