Describing 'GenericMethods' {
    Import-Module -Name $TestScriptPath\PSGenericMethods.psm1 -Force -ErrorAction Stop

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

            public static string DefaultParameterTest<T> (string required, string optional = "Default value")
            {
                return string.Format("'{0}', '{1}'", required, optional);
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
        }
'@

    Add-Type -TypeDefinition $cSharp -ErrorAction Stop

    
    Given 'A static method with no parameters' {
        It 'Returns the generic type''s full name' {
            Invoke-GenericMethod -Type TestClass -MethodName StaticMethodNoParameters -GenericType psobject |
            Should Equal ([psobject].FullName)
        }
    }

    Given 'A method with a generic return type' {
        It 'Returns the default value for Numeric types' {
            Invoke-GenericMethod -Type TestClass -MethodName GetDefaultValue -GenericType int |
            Should Equal 0
        }

        It 'Returns the default value for Boolean types' {
            Invoke-GenericMethod -Type TestClass -MethodName GetDefaultValue -GenericType bool |
            Should Equal $false
        }

        It 'Returns the default value for Reference types' {
            Invoke-GenericMethod -Type TestClass -MethodName GetDefaultValue -GenericType System.IO.FileInfo |
            Should Equal $null
        }
    }

    Given 'A method with optional parameters (default values)' {
        It 'Returns the specified value' {
            Invoke-GenericMethod -Type TestClass -MethodName DefaultParameterTest -GenericType string -ArgumentList 'Required Parameter', 'Optional Parameter' |
            Should Equal "'Required Parameter', 'Optional Parameter'"
        }

        It 'Returns the default value' {
            Invoke-GenericMethod -Type TestClass -MethodName DefaultParameterTest -GenericType string -ArgumentList 'Required Parameter' |
            Should Equal "'Required Parameter', 'Default value'"
        }
    }

    Given 'A method with parameters that are Generic types' {
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

    Given 'A method with a parameter that is an array of the method''s generic type' {
        It 'Resolves runtime types correctly' {
            Invoke-GenericMethod -Type TestClass -MethodName ArrayParameterTest -GenericType string -ArgumentList (,(New-Object string[](4))) |
            Should Equal System.String[]
        }
    }

    Given 'A method with "out" parameters' {
        It 'Assigns the default boolean value to the generic out parameter, and the value "Out Value" to the out string parameter.' {
            $string = $null
            $bool = $true

            Invoke-GenericMethod -Type TestClass -MethodName OutParameterTest -GenericType bool -ArgumentList ([ref]$bool, [ref]$string) |
            Should {
                param ($Value)
                $Value -eq 'OutParameterTest' -and $string -eq 'Out Value' -and $bool -eq $false
            }
            
        }
    }

    Given 'A method with "ref" parameters' {
        It 'Assigns the default boolean value to the generic ref parameter, and the value "Out Value" to the ref string parameter.' {
            $string = 'Original Value'
            $bool = $true

            Invoke-GenericMethod -Type TestClass -MethodName RefParameterTest -GenericType bool -ArgumentList ([ref]$bool, [ref]$string) |
            Should {
                param ($Value)
                $Value -eq "RefParameterTest: 'Original Value'" -and $string -eq 'Out Value' -and $bool -eq $false
            }
        }
    }

    Given 'A method with Nullable Ref parameters' {
        It 'Correctly resolves the runtime types, the original null value, and assigns a value of 5 to the reference parameter' {
            $ref = $null

            Invoke-GenericMethod -Type TestClass -MethodName NullableRefTest -GenericType string -ArgumentList @([ref] $ref) |
            Should {
                param ($Value)
                $Value -eq 'NullableRefTest: OriginalValue null' -and $ref -eq 5
            }
        }

        It 'Correctly resolves the runtime types, the original non-null value, and assigns a value of 5 to the reference parameter' {
            $ref = 10

            Invoke-GenericMethod -Type TestClass -MethodName NullableRefTest -GenericType string -ArgumentList @([ref] $ref) |
            Should {
                param ($Value)
                $Value -eq "NullableRefTest: OriginalValue '10'" -and $ref -eq 5
            }
        }

        It 'Performs type conversion when an exact method signature is not found' {
            $ref = 10L
            
            Invoke-GenericMethod -Type TestClass -MethodName NullableRefTest -GenericType string -ArgumentList @([ref] $ref) |
            Should {
                param ($Value)
                $Value -eq "NullableRefTest: OriginalValue '10'" -and $ref -eq 5
            }
        }
    }

    Given 'An instance method' {
        It 'Invokes the instance method using -InputObject' {
            $object = New-Object TestClass

            Invoke-GenericMethod -InputObject $object -MethodName InstanceMethodNoParameters -GenericType psobject |
            Should Equal ([psobject].FullName)
        }
        
        It 'Invokes the instance method using pipeline input' {
            $object = New-Object TestClass

            $object | Invoke-GenericMethod -MethodName InstanceMethodNoParameters -GenericType psobject |
            Should Equal ([psobject].FullName)
        }
    }
}