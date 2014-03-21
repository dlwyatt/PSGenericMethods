function Get-GenericParameterRuntimeType
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Type]
        $ParameterType,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $RuntimeType,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $GenericType
    )

    for ($i = 0; $i -lt $GenericType.Count; $i++)
    {
        if ($ParameterType -eq $GenericType[$i])
        {
            return $RuntimeType[$i]
        }
    }
}

function Get-GenericMethod
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Type]
        $Type,

        [Parameter(Mandatory = $true)]
        [string]
        $MethodName,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $GenericType,

        [Object[]]
        $ArgumentList = @(),

        [System.Reflection.BindingFlags]
        $BindingFlags = [System.Reflection.BindingFlags]::Default,

        [switch]
        $WithCoercion
    )

    foreach ($method in $Type.GetMethods($BindingFlags))
    {
        if (-not $method.IsGenericMethod -or $method.Name -ne $MethodName) { continue }
        if ($GenericType.Count -ne $method.GetGenericArguments().Count) { continue }

        $parameters = @($method.GetParameters())

        # TODO: This may not account for optional parameters with default values.  Need to check on that later.
        if ($parameters.Count -ne $ArgumentList.Count) { continue }

        $isMatch = $true

        for ($i = 0; $i -lt $parameters.Count; $i++)
        {
            if ($parameters[$i].ParameterType.IsGenericParameter)
            {
                $params = @{
                    ParameterType = $parameters[$i].ParameterType
                    RuntimeType   = $GenericType
                    GenericType   = $method.GetGenericArguments()
                }

                $runtimeType = Get-GenericParameterRuntimeType @params

                if ($null -eq $runtimeType)
                {
                    Write-Error "Could not runtime type of parameter $($parameters[$i].Name)"
                    return
                }
            }
            else
            {
                $runtimeType = $parameters[$i].ParameterType
            }
            

            if ($runtimeType.FullName -like 'System.Nullable``1*')
            {
                # TODO: This can probably be refactored so there's not duplicate coercion code.  Right now this is separate because
                # System.Nullable is a struct (IsValueType = $true), and the first version code considers $null arguments to be
                # a mismatch if the parameter's type is a Value type.

                $nullableType = $runtimeType.GetGenericArguments()[0]

                if ($null -eq $ArgumentList[$i] -or $ArgumentList[$i].GetType() -eq $nullableType)
                {
                    continue
                }

                $coercedValue = $ArgumentList[$i] -as $nullableType

                if (-not $WithCoercion -or $null -eq $coercedValue)
                {
                    $isMatch = $false
                    break
                }

                $ArgumentList[$i] = $coercedValue
            }
            else
            {
                if ($null -eq $ArgumentList[$i])
                {
                    if ($runtimeType.IsValueType)
                    {
                        $isMatch = $false
                        break
                    }
                }
                else
                {
                    # TODO:  Test to see if we need special code here for parameters that are themselves instances of generic types (for coercion)

                    if ($ArgumentList[$i].GetType() -eq $runtimeType) { continue }

                    $coercedValue = $ArgumentList[$i] -as $runtimeType
                    if (-not $WithCoercion -or $null -eq $coercedValue)
                    {
                        $isMatch = $false
                        break
                    }

                    $ArgumentList[$i] = $coercedValue
                }                    
            }

        } # for ($i = 0; $i -lt $parameters.Count; $i++)

        if ($isMatch)
        {
            return $method.MakeGenericMethod($GenericType)
        }

    } # foreach ($method in $Type.GetMethods($BindingFlags))

    if (-not $WithCoercion)
    {
        $null = $PSBoundParameters.Remove('WithCoercion')
        return Get-GenericMethod @PSBoundParameters -WithCoercion
    }

} # function Get-GenericMethod

function Invoke-GenericMethod
{
    [CmdletBinding(DefaultParameterSetName = 'Instance')]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Instance')]
        $InputObject,

        [Parameter(Mandatory = $true, ParameterSetName = 'Static')]
        [Type]
        $Type,

        [Parameter(Mandatory = $true)]
        [string]
        $MethodName,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $GenericType,

        [Object[]]
        $ArgumentList = @()
    )

    process
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            'Instance'
            {
                $_type  = $InputObject.GetType()
                $object = $InputObject
                $flags  = [System.Reflection.BindingFlags] 'Instance, Public'
            }

            'Static'
            {
                $_type  = $Type
                $object = $null
                $flags  = [System.Reflection.BindingFlags] 'Static, Public'
            }
        }

        $argList = $argumentList.Clone()

        $params = @{
            Type         = $_type
            BindingFlags = $flags
            MethodName   = $MethodName
            GenericType  = $GenericType
            ArgumentList = $argList
        }

        $method = Get-GenericMethod @params

        if ($null -eq $method)
        {
            Write-Error "No matching method was found"
            return
        }

        return $method.Invoke($object, $argList)

    } # process

} # function Invoke-GenericMethod

#
# Test Code
#

$cSharp = @'
    using System.Management.Automation;

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

        public static TOut StaticParameterlessCreateObject<TIn, TOut> (int? nullableTest, TIn ignore)
        {
            return default(TOut);
        }
    }
'@

Add-Type -TypeDefinition $cSharp

cls

$VerbosePreference = 'Continue'

Write-Verbose "Testing Static Method"
Invoke-GenericMethod -Type testClass -GenericType String -ArgumentList ('StaticTest', 12345) -MethodName StaticCreateObject | Out-Host

Write-Verbose 'Testing instance method'
$test = New-Object TestClass

$test | Invoke-GenericMethod -GenericType String -ArgumentList ('InstanceTest', 67890) -MethodName CreateObject | Out-Host
