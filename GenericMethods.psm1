#requires -Version 2.0

function Invoke-GenericMethod
{
    <#
    .Synopsis
       Invokes Generic methods on .NET Framework types
    .DESCRIPTION
       Allows the caller to invoke a Generic method on a .NET object or class with a single function call.  Invoke-GenericMethod handles identifying the proper method overload, parameters with default values, and to some extent, the same type conversion behavior you expect when calling a normal .NET Framework method from PowerShell.
    .PARAMETER InputObject
       The object on which to invoke an instance generic method.
    .PARAMETER Type
       The .NET class on which to invoke a static generic method.
    .PARAMETER MethodName
       The name of the generic method to be invoked.
    .PARAMETER GenericType
       One or more types which are specified when calling the generic method.  For example, if a method's signature is "string MethodName<T>();", and you want T to be a String, then you would pass "string" or ([string]) to the Type parameter of Invoke-GenericMethod.
    .PARAMETER ArgumentList
       The arguments to be passed on to the generic method when it is invoked.  The order of the arguments must match that of the .NET method's signature; named parameters are not currently supported.
    .EXAMPLE
       Invoke-GenericMethod -InputObject $someObject -MethodName SomeMethodName -GenericType string -ArgumentList $arg1,$arg2,$arg3

       Invokes a generic method on an object.  The signature of this method would be something like this (containing 3 arguments and a single Generic type argument):  object SomeMethodName<T>(object arg1, object arg2, object arg3);
    .EXAMPLE
       $someObject | Invoke-GenericMethod -MethodName SomeMethodName -GenericType string -ArgumentList $arg1,$arg2,$arg3

       Same as example 1, except $someObject is passed to the function via the pipeline.
    .EXAMPLE
       Invoke-GenericMethod -Type SomeClass -MethodName SomeMethodName -GenericType string,int -ArgumentList $arg1,$arg2,$arg3

       Invokes a static generic method on a class.  The signature of this method would be something like this (containing 3 arguments and two Generic type arguments):  static object SomeMethodName<T1,T2> (object arg1, object arg2, object arg3);
    .INPUTS
       System.Object
    .OUTPUTS
       System.Object
    .NOTES
       Known issues:

       Ref / Out parameters and [PSReference] objects are currently not working properly, and I don't think there's a way to fix that from within PowerShell.  I'll have to expand on the
       PSGenericTypes.MethodInvoker.InvokeMethod() C# code to account for that.
    #>

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
        $ArgumentList
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

        if ($null -ne $ArgumentList)
        {
            $argList = $ArgumentList.Clone()
        }
        else
        {
            $argList = @()
        }

        $params = @{
            Type         = $_type
            BindingFlags = $flags
            MethodName   = $MethodName
            GenericType  = $GenericType
            ArgumentList = [ref]$argList
        }

        $method = Get-GenericMethod @params

        if ($null -eq $method)
        {
            Write-Error "No matching method was found"
            return
        }

        # I'm not sure why, but PowerShell appears to be passing instances of PSObject when $argList contains generic types.  Instead of calling
        # $method.Invoke here from PowerShell, I had to write the PSGenericMethods.MethodInvoker.InvokeMethod helper code in C# to enumerate the
        # argument list and replace any instances of PSObject with their BaseObject before calling $method.Invoke().

        return [PSGenericMethods.MethodInvoker]::InvokeMethod($method, $object, $argList)

    } # process

} # function Invoke-GenericMethod

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

        [ref]
        $ArgumentList,

        [System.Reflection.BindingFlags]
        $BindingFlags = [System.Reflection.BindingFlags]::Default,

        [switch]
        $WithCoercion
    )

    if ($null -eq $ArgumentList.Value)
    {
        $originalArgList = @()
    }
    else
    {
        $originalArgList = @($ArgumentList.Value)
    }

    foreach ($method in $Type.GetMethods($BindingFlags))
    {
        $argList = $originalArgList.Clone()

        if (-not $method.IsGenericMethod -or $method.Name -ne $MethodName) { continue }
        if ($GenericType.Count -ne $method.GetGenericArguments().Count) { continue }

        if (Test-GenericMethodParameters -ParameterList $method.GetParameters() -ArgumentList ([ref]$argList) -GenericType $GenericType -WithCoercion:$WithCoercion)
        {
            $ArgumentList.Value = $argList
            return $method.MakeGenericMethod($GenericType)
        }
    }

    if (-not $WithCoercion)
    {
        $null = $PSBoundParameters.Remove('WithCoercion')
        return Get-GenericMethod @PSBoundParameters -WithCoercion
    }

} # function Get-GenericMethod

function Test-GenericMethodParameters
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Reflection.ParameterInfo[]]
        $ParameterList,

        [ref]
        $ArgumentList,

        [Parameter(Mandatory = $true)]
        [Type[]]
        $GenericType,

        [switch]
        $WithCoercion
    )

    if ($null -eq $ArgumentList.Value)
    {
        $argList = @()
    }
    else
    {
        $argList = @($ArgumentList.Value)
    }

    if ($ParameterList.Count -lt $argList.Count) { return $false }
    
    for ($i = 0; $i -lt $argList.Count; $i++)
    {
        $params = @{
            ParameterType = $ParameterList[$i].ParameterType
            RuntimeType   = $GenericType
            GenericType   = $method.GetGenericArguments()
        }

        $runtimeType = Resolve-RuntimeType @params

        if ($null -eq $runtimeType)
        {
            throw "Could not determine runtime type of parameter '$($ParameterList[$i].Name)'"
        }

        $argValue = $argList[$i]
        $argType = Get-Type $argValue

        $isByRef = $runtimeType.IsByRef
        if ($isByRef)
        {
            if ($argList[$i] -isnot [ref]) { return $false }

            $runtimeType = $runtimeType.GetElementType()
            $argValue = $argValue.Value
            $argType = Get-Type $argValue
        }

        $isNullNullable = $false

        while ($runtimeType.FullName -like 'System.Nullable``1*')
        {
            if ($null -eq $argValue)
            {
                $isNullNullable = $true
                break
            }

            $runtimeType = $runtimeType.GetGenericArguments()[0]
        }

        if ($isNullNullable) { continue }

        if ($null -eq $argValue)
        {
            if ($runtimeType.IsValueType)
            {
                return $false
            }
            else
            {
                continue
            }
        }
        else
        {
            if ($argType -ne $runtimeType)
            {
                $argValue = $argValue -as $runtimeType
                if (-not $WithCoercion -or $null -eq $argValue)  { return $false }
            }

            if ($isByRef)
            {
                $argList[$i].Value = $argValue
            }
            else
            {
                $argList[$i] = $argValue
            }
        }                    

    } # for ($i = 0; $i -lt $argList.Count; $i++)

    $defaults = New-Object System.Collections.ArrayList

    for ($i = $argList.Count; $i -lt $ParameterList.Count; $i++)
    {
        if (-not $ParameterList[$i].HasDefaultValue)  { return $false }
        $null = $defaults.Add($ParameterList[$i].DefaultValue)
    }

    $ArgumentList.Value = $argList + $defaults.ToArray()
    
    return $true

} # function Test-GenericMethodParameters

function Resolve-RuntimeType
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

    if ($ParameterType.IsByRef)
    {
        $elementType = Resolve-RuntimeType -ParameterType $ParameterType.GetElementType() -RuntimeType $RuntimeType -GenericType $GenericType
        return $elementType.MakeByRefType()
    }
    elseif ($ParameterType.IsGenericParameter)
    {
        for ($i = 0; $i -lt $GenericType.Count; $i++)
        {
            if ($ParameterType -eq $GenericType[$i])
            {
                return $RuntimeType[$i]
            }
        }
    }
    elseif ($ParameterType.IsArray)
    {
        $arrayType = $ParameterType
        $elementType = Resolve-RuntimeType -ParameterType $ParameterType.GetElementType() -RuntimeType $RuntimeType -GenericType $GenericType

        if ($ParameterType.GetElementType().IsGenericParameter)
        {
            $arrayRank = $arrayType.GetArrayRank()

            if ($arrayRank -eq 1)
            {
                $arrayType = $elementType.MakeArrayType()
            }
            else
            {
                $arrayType = $elementType.MakeArrayType($arrayRank)
            }
        }

        return $arrayType
    }
    elseif ($ParameterType.ContainsGenericParameters)
    {
        $genericArguments = $ParameterType.GetGenericArguments()
        $runtimeArguments = New-Object System.Collections.ArrayList

        foreach ($argument in $genericArguments)
        {
            $null = $runtimeArguments.Add((Resolve-RuntimeType -ParameterType $argument -RuntimeType $RuntimeType -GenericType $GenericType))
        }

        $definition = $ParameterType
        if (-not $definition.IsGenericTypeDefinition)
        {
            $definition = $definition.GetGenericTypeDefinition()
        }

        return $definition.MakeGenericType($runtimeArguments.ToArray())
    }
    else
    {
        return $ParameterType
    }
}

function Get-Type($object)
{
    if ($null -eq $object) { return $null }
    return $object.GetType()
}

Add-Type -ErrorAction Stop -TypeDefinition @'
    namespace PSGenericMethods
    {
        using System;
        using System.Reflection;
        using System.Management.Automation;

        public static class MethodInvoker
        {
            public static object InvokeMethod(MethodInfo method, object target, object[] arguments)
            {
                if (method == null) { throw new ArgumentNullException("method"); }

                object[] args = null;

                if (arguments != null)
                {
                    args = (object[])arguments.Clone();
                    for (int i = 0; i < args.Length; i++)
                    {
                        PSObject pso = args[i] as PSObject;
                        if (pso != null)
                        {
                            args[i] = pso.BaseObject;
                        }

                        PSReference psref = args[i] as PSReference;

                        if (psref != null)
                        {
                            args[i] = psref.Value;
                        }
                    }
                }

                object result = method.Invoke(target, args);

                for (int i = 0; i < arguments.Length; i++)
                {
                    PSReference psref = arguments[i] as PSReference;

                    if (psref != null)
                    {
                        psref.Value = args[i];
                    }
                }

                return result;
            }
        }
    }
'@

Export-ModuleMember -Function 'Invoke-GenericMethod'

# SIG # Begin signature block
# MIIhfgYJKoZIhvcNAQcCoIIhbzCCIWsCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUtIAIr8T97Qj9jfWJdKgW4nIS
# 8qmgghywMIIDtzCCAp+gAwIBAgIQDOfg5RfYRv6P5WD8G/AwOTANBgkqhkiG9w0B
# AQUFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMDYxMTEwMDAwMDAwWhcNMzExMTEwMDAwMDAwWjBlMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3Qg
# Q0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCtDhXO5EOAXLGH87dg
# +XESpa7cJpSIqvTO9SA5KFhgDPiA2qkVlTJhPLWxKISKityfCgyDF3qPkKyK53lT
# XDGEKvYPmDI2dsze3Tyoou9q+yHyUmHfnyDXH+Kx2f4YZNISW1/5WBg1vEfNoTb5
# a3/UsDg+wRvDjDPZ2C8Y/igPs6eD1sNuRMBhNZYW/lmci3Zt1/GiSw0r/wty2p5g
# 0I6QNcZ4VYcgoc/lbQrISXwxmDNsIumH0DJaoroTghHtORedmTpyoeb6pNnVFzF1
# roV9Iq4/AUaG9ih5yLHa5FcXxH4cDrC0kqZWs72yl+2qp/C3xag/lRbQ/6GW6whf
# GHdPAgMBAAGjYzBhMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0G
# A1UdDgQWBBRF66Kv9JLLgjEtUYunpyGd823IDzAfBgNVHSMEGDAWgBRF66Kv9JLL
# gjEtUYunpyGd823IDzANBgkqhkiG9w0BAQUFAAOCAQEAog683+Lt8ONyc3pklL/3
# cmbYMuRCdWKuh+vy1dneVrOfzM4UKLkNl2BcEkxY5NM9g0lFWJc1aRqoR+pWxnmr
# EthngYTffwk8lOa4JiwgvT2zKIn3X/8i4peEH+ll74fg38FnSbNd67IJKusm7Xi+
# fT8r87cmNW1fiQG2SVufAQWbqz0lwcy2f8Lxb4bG+mRo64EtlOtCt/qMHt1i8b5Q
# Z7dsvfPxH2sMNgcWfzd8qVttevESRmCD1ycEvkvOl77DZypoEd+A5wwzZr8TDRRu
# 838fYxAe+o0bJW1sj6W3YQGx0qMmoRBxna3iw/nDmVG3KwcIzi7mULKn+gpFL6Lw
# 8jCCBQswggPzoAMCAQICEAOiV15N2F/TLPzy+oVrWjMwDQYJKoZIhvcNAQEFBQAw
# bzELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQ
# d3d3LmRpZ2ljZXJ0LmNvbTEuMCwGA1UEAxMlRGlnaUNlcnQgQXNzdXJlZCBJRCBD
# b2RlIFNpZ25pbmcgQ0EtMTAeFw0xNDA1MDUwMDAwMDBaFw0xNTA1MTMxMjAwMDBa
# MGExCzAJBgNVBAYTAkNBMQswCQYDVQQIEwJPTjERMA8GA1UEBxMIQnJhbXB0b24x
# GDAWBgNVBAoTD0RhdmlkIExlZSBXeWF0dDEYMBYGA1UEAxMPRGF2aWQgTGVlIFd5
# YXR0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvcX51YAyViQE16mg
# +IVQCQ0O8QC/wXBzTMPirnoGK9TThmxQIYgtcekZ5Xa/dWpW0xKKjaS6dRwYYXET
# pzozoMWZbFDVrgKaqtuZNu9TD6rqK/QKf4iL/eikr0NIUL4CoSEQDeGLXDw7ntzZ
# XKM86RuPw6MlDapfFQQFIMjsT7YaoqQNTOxhbiFoHVHqP7xL3JTS7TApa/RnNYyl
# O7SQ7TSNsekiXGwUNxPqt6UGuOP0nyR+GtNiBcPfeUi+XaqjjBmpqgDbkEIMLDuf
# fDO54VKvDLl8D2TxTFOcKZv61IcToOs+8z1sWTpMWI2MBuLhRR3A6iIhvilTYRBI
# iX5FZQIDAQABo4IBrzCCAaswHwYDVR0jBBgwFoAUe2jOKarAF75JeuHlP9an90WP
# NTIwHQYDVR0OBBYEFDS4+PmyUp+SmK2GR+NCMiLd+DpvMA4GA1UdDwEB/wQEAwIH
# gDATBgNVHSUEDDAKBggrBgEFBQcDAzBtBgNVHR8EZjBkMDCgLqAshipodHRwOi8v
# Y3JsMy5kaWdpY2VydC5jb20vYXNzdXJlZC1jcy1nMS5jcmwwMKAuoCyGKmh0dHA6
# Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9hc3N1cmVkLWNzLWcxLmNybDBCBgNVHSAEOzA5
# MDcGCWCGSAGG/WwDATAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2Vy
# dC5jb20vQ1BTMIGCBggrBgEFBQcBAQR2MHQwJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBMBggrBgEFBQcwAoZAaHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEQ29kZVNpZ25pbmdDQS0xLmNydDAM
# BgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBBQUAA4IBAQBbzAp8wys0A5LcuENslW0E
# oz7rc0A8h+XgjJWdJOFRohE1mZRFpdkVxM0SRqw7IzlSFtTMCsVVPNwU6O7y9rCY
# x5agx3CJBkJVDR/Y7DcOQTmmHy1zpcrKAgTznZuKUQZLpoYz/bA+Uh+bvXB9woCA
# IRbchos1oxC+7/gjuxBMKh4NM+9NIvWs6qpnH5JeBidQDQXp3flPkla+MKrPTL/T
# /amgna5E+9WHWnXbMFCpZ5n1bI1OvgNVZlYC/JTa4fjPEk8d16jYVP4GlRz/QUYI
# y6IAGc/z6xpkdtpXWVCbW0dCd5ybfUYTaeCJumGpS/HSJ7JcTZj694QDOKNvhfrm
# MIIGajCCBVKgAwIBAgIQA5/t7ct5W43tMgyJGfA2iTANBgkqhkiG9w0BAQUFADBi
# MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
# d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBBc3N1cmVkIElEIENB
# LTEwHhcNMTMwNTIxMDAwMDAwWhcNMTQwNjA0MDAwMDAwWjBHMQswCQYDVQQGEwJV
# UzERMA8GA1UEChMIRGlnaUNlcnQxJTAjBgNVBAMTHERpZ2lDZXJ0IFRpbWVzdGFt
# cCBSZXNwb25kZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC6aUqB
# TW+lFBaqis1nvku/xmmPWBzgeegenVgmmNpc1Hyj+dsrjBI2w/z5ZAaxu8KomAoX
# DeGV60C065ZtmL+mj3nPvIqSe22cGAZR2KUYUzIBJxlh6IRB38bw6Mr+d61f2J57
# jGBvhVxGvWvnD4DO5wPDfDHPt2VVxvvgmQjkc1r7l9rQTL60tsYPfyaSqbj8OO60
# 5DqkSNBM6qlGJ1vPkhGTnBan/tKtHyLFHqzBce+8StsBCUTfmBwtZ7qoigMzyVG1
# 9wJNCaRN/oBexddFw30IqgEzzDPYTzAW5P8iMi7rfjvw+R4y65Ul0vL+bVSEutXl
# 1NHdG6+9WXuUhTABAgMBAAGjggM1MIIDMTAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0T
# AQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDCCAb8GA1UdIASCAbYwggGy
# MIIBoQYJYIZIAYb9bAcBMIIBkjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGln
# aWNlcnQuY29tL0NQUzCCAWQGCCsGAQUFBwICMIIBVh6CAVIAQQBuAHkAIAB1AHMA
# ZQAgAG8AZgAgAHQAaABpAHMAIABDAGUAcgB0AGkAZgBpAGMAYQB0AGUAIABjAG8A
# bgBzAHQAaQB0AHUAdABlAHMAIABhAGMAYwBlAHAAdABhAG4AYwBlACAAbwBmACAA
# dABoAGUAIABEAGkAZwBpAEMAZQByAHQAIABDAFAALwBDAFAAUwAgAGEAbgBkACAA
# dABoAGUAIABSAGUAbAB5AGkAbgBnACAAUABhAHIAdAB5ACAAQQBnAHIAZQBlAG0A
# ZQBuAHQAIAB3AGgAaQBjAGgAIABsAGkAbQBpAHQAIABsAGkAYQBiAGkAbABpAHQA
# eQAgAGEAbgBkACAAYQByAGUAIABpAG4AYwBvAHIAcABvAHIAYQB0AGUAZAAgAGgA
# ZQByAGUAaQBuACAAYgB5ACAAcgBlAGYAZQByAGUAbgBjAGUALjALBglghkgBhv1s
# AxUwHwYDVR0jBBgwFoAUFQASKxOYspkH7R7for5XDStnAs0wHQYDVR0OBBYEFGMv
# yd95knu1I8q74aTuM37j4p36MH0GA1UdHwR2MHQwOKA2oDSGMmh0dHA6Ly9jcmwz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRENBLTEuY3JsMDigNqA0hjJo
# dHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURDQS0xLmNy
# bDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2lj
# ZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0QXNzdXJlZElEQ0EtMS5jcnQwDQYJKoZIhvcNAQEFBQADggEBAKt0
# vUAATHYVJVc90xwD/31FyEUSZucoZWDY3zuz+g3BrDOP9IG5YfGd+5hV195HQ7qA
# PfFIzD9nMFYfzvTQTIS9h6SexeEPqAZd0C9uXtwZ6PCH6uBOrz1sII5zb37Whxjg
# htOa/J7qjHLpQQ+4cbU4LPgpstUcop0b7F8quNw3IOHLu/DQbGyls8ufSvZU4yY0
# PS64wSsct/bDPf7RLR5Q9JTI+P3uc9tJtRv09f+lkME5FBvY7XEbapj7+kCaRKkp
# DlVeeLi3pIPDcAHwZkDlrnk04StNA6Et5ttUYhjt1QmLoqrWDMhPGr6ZJXhpmYnU
# WYne34jw02dedKWdpkQwggajMIIFi6ADAgECAhAPqEkGFdcAoL4hdv3F7G29MA0G
# CSqGSIb3DQEBBQUAMGUxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xJDAiBgNVBAMTG0RpZ2lDZXJ0
# IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0xMTAyMTExMjAwMDBaFw0yNjAyMTAxMjAw
# MDBaMG8xCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xLjAsBgNVBAMTJURpZ2lDZXJ0IEFzc3VyZWQg
# SUQgQ29kZSBTaWduaW5nIENBLTEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCcfPmgjwrKiUtTmjzsGSJ/DMv3SETQPyJumk/6zt/G0ySR/6hSk+dy+PFG
# hpTFqxf0eH/Ler6QJhx8Uy/lg+e7agUozKAXEUsYIPO3vfLcy7iGQEUfT/k5mNM7
# 629ppFwBLrFm6aa43Abero1i/kQngqkDw/7mJguTSXHlOG1O/oBcZ3e11W9mZJRr
# u4hJaNjR9H4hwebFHsnglrgJlflLnq7MMb1qWkKnxAVHfWAr2aFdvftWk+8b/HL5
# 3z4y/d0qLDJG2l5jvNC4y0wQNfxQX6xDRHz+hERQtIwqPXQM9HqLckvgVrUTtmPp
# P05JI+cGFvAlqwH4KEHmx9RkO12rAgMBAAGjggNDMIIDPzAOBgNVHQ8BAf8EBAMC
# AYYwEwYDVR0lBAwwCgYIKwYBBQUHAwMwggHDBgNVHSAEggG6MIIBtjCCAbIGCGCG
# SAGG/WwDMIIBpDA6BggrBgEFBQcCARYuaHR0cDovL3d3dy5kaWdpY2VydC5jb20v
# c3NsLWNwcy1yZXBvc2l0b3J5Lmh0bTCCAWQGCCsGAQUFBwICMIIBVh6CAVIAQQBu
# AHkAIAB1AHMAZQAgAG8AZgAgAHQAaABpAHMAIABDAGUAcgB0AGkAZgBpAGMAYQB0
# AGUAIABjAG8AbgBzAHQAaQB0AHUAdABlAHMAIABhAGMAYwBlAHAAdABhAG4AYwBl
# ACAAbwBmACAAdABoAGUAIABEAGkAZwBpAEMAZQByAHQAIABDAFAALwBDAFAAUwAg
# AGEAbgBkACAAdABoAGUAIABSAGUAbAB5AGkAbgBnACAAUABhAHIAdAB5ACAAQQBn
# AHIAZQBlAG0AZQBuAHQAIAB3AGgAaQBjAGgAIABsAGkAbQBpAHQAIABsAGkAYQBi
# AGkAbABpAHQAeQAgAGEAbgBkACAAYQByAGUAIABpAG4AYwBvAHIAcABvAHIAYQB0
# AGUAZAAgAGgAZQByAGUAaQBuACAAYgB5ACAAcgBlAGYAZQByAGUAbgBjAGUALjAS
# BgNVHRMBAf8ECDAGAQH/AgEAMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MIGB
# BgNVHR8EejB4MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRBc3N1cmVkSURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3JsNC5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMB0GA1UdDgQWBBR7aM4p
# qsAXvkl64eU/1qf3RY81MjAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823I
# DzANBgkqhkiG9w0BAQUFAAOCAQEAe3IdZP+IyDrBt+nnqcSHu9uUkteQWTP6K4fe
# qFuAJT8Tj5uDG3xDxOaM3zk+wxXssNo7ISV7JMFyXbhHkYETRvqcP2pRON60Jcvw
# q9/FKAFUeRBGJNE4DyahYZBNur0o5j/xxKqb9to1U0/J8j3TbNwj7aqgTWcJ8zqA
# PTz7NkyQ53ak3fI6v1Y1L6JMZejg1NrRx8iRai0jTzc7GZQY1NWcEDzVsRwZ/4/I
# a5ue+K6cmZZ40c2cURVbQiZyWo0KSiOSQOiG3iLCkzrUm2im3yl/Brk8Dr2fxIac
# gkdCcTKGCZlyCXlLnXFp9UH/fzl3ZPGEjb6LHrJ9aKOlkLEM/zCCBs0wggW1oAMC
# AQICEAb9+QOWA63qAArrPye7uhswDQYJKoZIhvcNAQEFBQAwZTELMAkGA1UEBhMC
# VVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0
# LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNzdXJlZCBJRCBSb290IENBMB4XDTA2
# MTExMDAwMDAwMFoXDTIxMTExMDAwMDAwMFowYjELMAkGA1UEBhMCVVMxFTATBgNV
# BAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8G
# A1UEAxMYRGlnaUNlcnQgQXNzdXJlZCBJRCBDQS0xMIIBIjANBgkqhkiG9w0BAQEF
# AAOCAQ8AMIIBCgKCAQEA6IItmfnKwkKVpYBzQHDSnlZUXKnE0kEGj8kz/E1FkVyB
# n+0snPgWWd+etSQVwpi5tHdJ3InECtqvy15r7a2wcTHrzzpADEZNk+yLejYIA6sM
# NP4YSYL+x8cxSIB8HqIPkg5QycaH6zY/2DDD/6b3+6LNb3Mj/qxWBZDwMiEWicZw
# iPkFl32jx0PdAug7Pe2xQaPtP77blUjE7h6z8rwMK5nQxl0SQoHhg26Ccz8mSxSQ
# rllmCsSNvtLOBq6thG9IhJtPQLnxTPKvmPv2zkBdXPao8S+v7Iki8msYZbHBc63X
# 8djPHgp0XEK4aH631XcKJ1Z8D2KkPzIUYJX9BwSiCQIDAQABo4IDejCCA3YwDgYD
# VR0PAQH/BAQDAgGGMDsGA1UdJQQ0MDIGCCsGAQUFBwMBBggrBgEFBQcDAgYIKwYB
# BQUHAwMGCCsGAQUFBwMEBggrBgEFBQcDCDCCAdIGA1UdIASCAckwggHFMIIBtAYK
# YIZIAYb9bAABBDCCAaQwOgYIKwYBBQUHAgEWLmh0dHA6Ly93d3cuZGlnaWNlcnQu
# Y29tL3NzbC1jcHMtcmVwb3NpdG9yeS5odG0wggFkBggrBgEFBQcCAjCCAVYeggFS
# AEEAbgB5ACAAdQBzAGUAIABvAGYAIAB0AGgAaQBzACAAQwBlAHIAdABpAGYAaQBj
# AGEAdABlACAAYwBvAG4AcwB0AGkAdAB1AHQAZQBzACAAYQBjAGMAZQBwAHQAYQBu
# AGMAZQAgAG8AZgAgAHQAaABlACAARABpAGcAaQBDAGUAcgB0ACAAQwBQAC8AQwBQ
# AFMAIABhAG4AZAAgAHQAaABlACAAUgBlAGwAeQBpAG4AZwAgAFAAYQByAHQAeQAg
# AEEAZwByAGUAZQBtAGUAbgB0ACAAdwBoAGkAYwBoACAAbABpAG0AaQB0ACAAbABp
# AGEAYgBpAGwAaQB0AHkAIABhAG4AZAAgAGEAcgBlACAAaQBuAGMAbwByAHAAbwBy
# AGEAdABlAGQAIABoAGUAcgBlAGkAbgAgAGIAeQAgAHIAZQBmAGUAcgBlAG4AYwBl
# AC4wCwYJYIZIAYb9bAMVMBIGA1UdEwEB/wQIMAYBAf8CAQAweQYIKwYBBQUHAQEE
# bTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYB
# BQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3Vy
# ZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmwzLmRp
# Z2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0
# dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5j
# cmwwHQYDVR0OBBYEFBUAEisTmLKZB+0e36K+Vw0rZwLNMB8GA1UdIwQYMBaAFEXr
# oq/0ksuCMS1Ri6enIZ3zbcgPMA0GCSqGSIb3DQEBBQUAA4IBAQBGUD7Jtygkpzgd
# tlspr1LPUukxR6tWXHvVDQtBs+/sdR90OPKyXGGinJXDUOSCuSPRujqGcq04eKx1
# XRcXNHJHhZRW0eu7NoR3zCSl8wQZVann4+erYs37iy2QwsDStZS9Xk+xBdIOPRqp
# FFumhjFiqKgz5Js5p8T1zh14dpQlc+Qqq8+cdkvtX8JLFuRLcEwAiR78xXm8TBJX
# /l/hHrwCXaj++wc4Tw3GXZG5D2dFzdaD7eeSDY2xaYxP+1ngIw/Sqq4AfO6cQg7P
# kdcntxbuD8O9fAqg7iwIVYUiuOsYGk38KiGtSTGDR5V3cdyxG0tLHBCcdxTBnU8v
# WpUIKRAmMYIEODCCBDQCAQEwgYMwbzELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERp
# Z2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEuMCwGA1UEAxMl
# RGlnaUNlcnQgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EtMQIQA6JXXk3YX9Ms
# /PL6hWtaMzAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZ
# BgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYB
# BAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUxLmjlCxEjCuCd+KMFCa7zqqA/VcwDQYJ
# KoZIhvcNAQEBBQAEggEARgAaKyL6b5cCQaNQlTU4kPDlCfXs8BfAHZWNg22ZJcU7
# rR3L8IN0FZwnh0a/JrodaNvKGCuGkZ3K6tTS/JaOKQPCnNQAfkZuxVujTnjzfc0R
# GvwPjwy6MADdGUAH1/Qq7FJjSvjZQ1Orih1RvnsngyibMBE2IRTe5vrNJpow7ynE
# 4HcAnofe60wvdiHIUtvRF4Ei7Hm87IZXd2dL9gN0HqZdvrwMaK5rwDl8Bb5tnQC6
# 3s20samLkJ87yYmIU5wqAlS4BGUU6hTvx8fO/NYvyVLXdUnlRVJMfOqdGWDJtCP2
# kwaOQdjdPEYeS5yzL/zJKS1avkeBMAelbbdtzWSX9qGCAg8wggILBgkqhkiG9w0B
# CQYxggH8MIIB+AIBATB2MGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IEFzc3VyZWQgSUQgQ0EtMQIQA5/t7ct5W43tMgyJGfA2iTAJBgUrDgMCGgUA
# oF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTQw
# NTA4MTc1MTM0WjAjBgkqhkiG9w0BCQQxFgQUluh0V0SdLbf5HqjN+qDY+0lDM8Aw
# DQYJKoZIhvcNAQEBBQAEggEAhH/IcHdLVwWp3rQdc25kFG7+QyHu1c69SqBRYUzQ
# VJKl+eLH1qsBwQJ8R6hKbMhwUafZPX4GXZbgGPPCe4I1DmcDnrl1uuHbpOpuTMz/
# iK1+yXokvDyEqbRKvg6aXyrhWfHfTfLKZGHNrdOpIevy6B3zF5w52NWPGwA92x1X
# 2tjNjOklYOhD70bClGqoiWvhJr9mQs6QqOWceZLiv1yI0TV3t8aj2uXpoKplobur
# 7xNfL39zC/py4Unc3xakLLHGt4pAzIzCC/pXXnFLJqaCbstOo/NH+yyHkNnb1M/3
# Fb9y3ybMCa/ICsn9t0Z84ejTPZyxT69WXzdyNradQU1dlg==
# SIG # End signature block
