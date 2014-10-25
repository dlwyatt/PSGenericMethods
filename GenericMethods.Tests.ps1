$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path

Import-Module -Name $scriptRoot\GenericMethods.psm1 -Force -ErrorAction Stop

Describe 'GenericMethods' {
    $cSharp = @'
        using System;
        using System.Management.Automation;
        using System.Collections.Generic;

        public class TestClass
        {
            public string InstanceMethodNoParameters<T> ()
            {
                return typeof(T).FullName;
            }

            public static string StaticMethodNoParameters<T> ()
            {
                return typeof(T).FullName;
            }

            public static T GetDefaultValue<T> ()
            {
                return default(T);
            }

            public static string GenericTypeParameterTest<T> (List<T> parameter)
            {
                if (parameter == null) { throw new ArgumentNullException("parameter"); }
                return parameter.GetType().FullName;
            }

            public static string GenericTypeParameterTest2<T> (List<string> parameter)
            {
                if (parameter == null) { throw new ArgumentNullException("parameter"); }
                return parameter.GetType().FullName;
            }

            public static string GenericTypeParameterTest3<T> (List<List<T>> parameter)
            {
                if (parameter == null) { throw new ArgumentNullException("parameter"); }
                return parameter.GetType().FullName;
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

            public static string NullableRefTest<T>(ref int? parameter)
            {
                string message;

                if (parameter.HasValue)
                {
                    message = String.Format("NullableRefTest: OriginalValue '{0}'", parameter.Value);
                }
                else
                {
                    message = "NullableRefTest: OriginalValue null";
                }

                parameter = 5;
                return message;
            }

            public static string ParamsArgumentTest<T>(int required, params string[] values)
            {
                return string.Format("T: {0}, required: {1}, values: {2}", typeof(T).FullName, required, string.Join(" ", values));
            }
        }
'@

    Add-Type -TypeDefinition $cSharp -ErrorAction Stop

    if ($PSVersionTable.PSVersion.Major -ge 3)
    {
        $cSharp = @'
            using System;
            using System.Management.Automation;
            using System.Collections.Generic;

            public class TestClass2
            {
                public static string DefaultParameterTest<T> (string required, string optional = "Default value")
                {
                    return string.Format("'{0}', '{1}'", required, optional);
                }
            }
'@

        Add-Type -TypeDefinition $cSharp -ErrorAction Stop
    }


    Context 'A static method with no parameters' {
        It 'Returns the generic type''s full name' {
            Invoke-GenericMethod -Type TestClass -MethodName StaticMethodNoParameters -GenericType psobject |
            Should Be ([psobject].FullName)
        }
    }

    Context 'A method with a generic return type' {
        It 'Returns the default value for Numeric types' {
            Invoke-GenericMethod -Type TestClass -MethodName GetDefaultValue -GenericType int |
            Should Be 0
        }

        It 'Returns the default value for Boolean types' {
            Invoke-GenericMethod -Type TestClass -MethodName GetDefaultValue -GenericType bool |
            Should Be $false
        }

        It 'Returns the default value for Reference types' {
            Invoke-GenericMethod -Type TestClass -MethodName GetDefaultValue -GenericType System.IO.FileInfo |
            Should Be $null
        }
    }

    if ($PSVersionTable.PSVersion.Major -ge 3)
    {
        Context 'A method with optional parameters (default values)' {
            It 'Returns the specified value' {
                Invoke-GenericMethod -Type TestClass2 -MethodName DefaultParameterTest -GenericType string -ArgumentList 'Required Parameter', 'Optional Parameter' |
                Should Be "'Required Parameter', 'Optional Parameter'"
            }

            It 'Returns the default value' {
                Invoke-GenericMethod -Type TestClass2 -MethodName DefaultParameterTest -GenericType string -ArgumentList 'Required Parameter' |
                Should Be "'Required Parameter', 'Default value'"
            }
        }
    }

    Context 'A method with parameters that are Generic types' {
        It 'Resolves the runtime types correctly (Test 1: Generic parameter type based on method generic type)' {
            Invoke-GenericMethod -Type TestClass -MethodName GenericTypeParameterTest -GenericType string -ArgumentList (,(New-Object System.Collections.Generic.List[string])) |
            Should Match '^System\.Collections\.Generic\.List`1\[\[System\.String'
        }

        It 'Resolves the runtime types correctly (Test 2: Generic parameter type not based on method generic type)' {
            Invoke-GenericMethod -Type TestClass -MethodName GenericTypeParameterTest2 -GenericType string -ArgumentList (,(New-Object System.Collections.Generic.List[string])) |
            Should Match '^System\.Collections\.Generic\.List`1\[\[System\.String'
        }

        It 'Resolves the runtime types correctly (Test 3: Nested generic type)' {
            Invoke-GenericMethod -Type TestClass -MethodName GenericTypeParameterTest3 -GenericType string -ArgumentList (,(New-Object System.Collections.Generic.List[System.Collections.Generic.List[string]])) |
            Should Match '^System\.Collections\.Generic\.List`1\[\[System\.Collections\.Generic\.List`1\[\[System\.String'
        }
    }

    Context 'A method with a parameter that is an array of the method''s generic type' {
        It 'Resolves runtime types correctly' {
            Invoke-GenericMethod -Type TestClass -MethodName ArrayParameterTest -GenericType string -ArgumentList (,(New-Object string[](4))) |
            Should Be 'System.String[]'
        }
    }

    Context 'A method with "out" parameters' {
        It 'Assigns the default boolean value to the generic out parameter, and the value "Out Value" to the out string parameter.' {
            $string = $null
            $bool = $true

            $result = Invoke-GenericMethod -Type TestClass -MethodName OutParameterTest -GenericType bool -ArgumentList ([ref]$bool, [ref]$string)

            $result | Should Be 'OutParameterTest'
            $string | Should Be 'Out Value'
            $bool | Should Be $false
        }
    }

    Context 'A method with "ref" parameters' {
        It 'Assigns the default boolean value to the generic ref parameter, and the value "Out Value" to the ref string parameter.' {
            $string = 'Original Value'
            $bool = $true

            $result = Invoke-GenericMethod -Type TestClass -MethodName RefParameterTest -GenericType bool -ArgumentList ([ref]$bool, [ref]$string)

            $result | Should Be "RefParameterTest: 'Original Value'"
            $string | Should Be 'Out Value'
            $bool | Should Be $false
        }
    }

    Context 'A method with Nullable Ref parameters' {
        It 'Correctly resolves the runtime types, the original null value, and assigns a value of 5 to the reference parameter' {
            $ref = $null
            $result = Invoke-GenericMethod -Type TestClass -MethodName NullableRefTest -GenericType string -ArgumentList @([ref] $ref)

            $result | Should Be 'NullableRefTest: OriginalValue null'
            $ref | Should Be 5
        }

        It 'Correctly resolves the runtime types, the original non-null value, and assigns a value of 5 to the reference parameter' {
            $ref = 10
            $result = Invoke-GenericMethod -Type TestClass -MethodName NullableRefTest -GenericType string -ArgumentList @([ref] $ref)

            $result | Should Be "NullableRefTest: OriginalValue '10'"
            $ref | Should Be 5
        }

        It 'Performs type conversion when an exact method signature is not found' {
            $ref = 10L
            $result = Invoke-GenericMethod -Type TestClass -MethodName NullableRefTest -GenericType string -ArgumentList @([ref] $ref)

            $result | Should Be "NullableRefTest: OriginalValue '10'"
            $ref | Should Be 5
        }
    }

    Context 'An instance method' {
        It 'Invokes the instance method using -InputObject' {
            $object = New-Object TestClass

            Invoke-GenericMethod -InputObject $object -MethodName InstanceMethodNoParameters -GenericType psobject |
            Should Be ([psobject].FullName)
        }

        It 'Invokes the instance method using pipeline input' {
            $object = New-Object TestClass

            $object | Invoke-GenericMethod -MethodName InstanceMethodNoParameters -GenericType psobject |
            Should Be ([psobject].FullName)
        }
    }

    Context 'Method with params argument' {
        $arguments = 10, 'One', 'Two', 'Three', 'Four', 'Five'

        It 'Invokes the method with a params argument' {
            $result = Invoke-GenericMethod -Type TestClass -MethodName ParamsArgumentTest -GenericType object -ArgumentList $arguments -ErrorAction Stop
            $result | Should Be 'T: System.Object, required: 10, values: One Two Three Four Five'
        }
    }
}
