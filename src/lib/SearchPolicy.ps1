Set-StrictMode -Version Latest

if (-not (Get-Command Write-STCLog -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Logging.ps1')
}

if (-not (Get-Command Get-SamsungTDrive -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'DriveDetection.ps1')
}

function Initialize-STCWindowsSearchApi {
    [CmdletBinding()]
    param()

    if ('STC.WindowsSearch.SearchApi' -as [type]) {
        return
    }

    $code = @'
using System;
using System.Runtime.InteropServices;

namespace STC.WindowsSearch {
    [ComImport, Guid("7D096C5F-AC08-4F1F-BEB7-5C22C517CE39")]
    public class CSearchManager { }

    [ComImport, Guid("AB310581-AC80-11D1-8DF3-00C04FB6EF50"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISearchCatalogManager {
        [PreserveSig] int get_Name([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
        [PreserveSig] int GetParameter([MarshalAs(UnmanagedType.LPWStr)] string pszName, out IntPtr ppValue);
        [PreserveSig] int SetParameter([MarshalAs(UnmanagedType.LPWStr)] string pszName, IntPtr pValue);
        [PreserveSig] int GetCatalogStatus(out int pStatus, out int pPausedReason);
        [PreserveSig] int Reset();
        [PreserveSig] int Reindex();
        [PreserveSig] int ReindexMatchingURLs([MarshalAs(UnmanagedType.LPWStr)] string pszPattern);
        [PreserveSig] int ReindexSearchRoot([MarshalAs(UnmanagedType.LPWStr)] string pszRootURL);
        [PreserveSig] int put_ConnectTimeout(uint dwConnectTimeout);
        [PreserveSig] int get_ConnectTimeout(out uint pdwConnectTimeout);
        [PreserveSig] int put_DataTimeout(uint dwDataTimeout);
        [PreserveSig] int get_DataTimeout(out uint pdwDataTimeout);
        [PreserveSig] int NumberOfItems(out int plCount);
        [PreserveSig] int NumberOfItemsToIndex(out int plIncrementalCount, out int plNotificationQueue, out int plHighPriorityQueue);
        [PreserveSig] int URLBeingIndexed([MarshalAs(UnmanagedType.LPWStr)] string pszUrl);
        [PreserveSig] int GetURLIndexingState([MarshalAs(UnmanagedType.LPWStr)] string pszURL, out uint pdwState);
        [PreserveSig] int GetPersistentItemsChangedSink(out IntPtr ppISearchPersistentItemsChangedSink);
        [PreserveSig] int RegisterViewForNotification([MarshalAs(UnmanagedType.LPWStr)] string pszView, IntPtr pViewChangedSink, out uint pdwCookie);
        [PreserveSig] int GetItemsChangedSink(IntPtr pISearchNotifyInlineSite, ref Guid riid, out IntPtr ppv, out Guid pGUIDCatalogResetSignature, out Guid pGUIDCheckPointSignature, out uint pdwLastCheckPointNumber);
        [PreserveSig] int UnregisterViewForNotification(uint dwCookie);
        [PreserveSig] int SetExtensionClusion([MarshalAs(UnmanagedType.LPWStr)] string pszExtension, [MarshalAs(UnmanagedType.Bool)] bool fExclude);
        [PreserveSig] int EnumerateExcludedExtensions(out IntPtr ppExtensions);
        [PreserveSig] int GetQueryHelper(out IntPtr ppSearchQueryHelper);
        [PreserveSig] int put_DiacriticSensitivity([MarshalAs(UnmanagedType.Bool)] bool fDiacriticSensitive);
        [PreserveSig] int get_DiacriticSensitivity([MarshalAs(UnmanagedType.Bool)] out bool pfDiacriticSensitive);
        [PreserveSig] int GetCrawlScopeManager(out ISearchCrawlScopeManager ppCrawlScopeManager);
    }

    [ComImport, Guid("AB310581-AC80-11D1-8DF3-00C04FB6EF55"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISearchCrawlScopeManager {
        [PreserveSig] int AddDefaultScopeRule([MarshalAs(UnmanagedType.LPWStr)] string pszURL, [MarshalAs(UnmanagedType.Bool)] bool fInclude, uint fFollowFlags);
        [PreserveSig] int AddRoot(IntPtr pSearchRoot);
        [PreserveSig] int RemoveRoot([MarshalAs(UnmanagedType.LPWStr)] string pszURL);
        [PreserveSig] int EnumerateRoots(out IntPtr ppSearchRoots);
        [PreserveSig] int AddHierarchicalScope([MarshalAs(UnmanagedType.LPWStr)] string pszURL, [MarshalAs(UnmanagedType.Bool)] bool fInclude, [MarshalAs(UnmanagedType.Bool)] bool fDefault, [MarshalAs(UnmanagedType.Bool)] bool fOverrideChildren);
        [PreserveSig] int AddUserScopeRule([MarshalAs(UnmanagedType.LPWStr)] string pszURL, [MarshalAs(UnmanagedType.Bool)] bool fInclude, [MarshalAs(UnmanagedType.Bool)] bool fOverrideChildren, uint fFollowFlags);
        [PreserveSig] int RemoveScopeRule([MarshalAs(UnmanagedType.LPWStr)] string pszRule);
        [PreserveSig] int EnumerateScopeRules(out IntPtr ppSearchScopeRules);
        [PreserveSig] int HasParentScopeRule([MarshalAs(UnmanagedType.LPWStr)] string pszURL, [MarshalAs(UnmanagedType.Bool)] out bool pfHasParentRule);
        [PreserveSig] int HasChildScopeRule([MarshalAs(UnmanagedType.LPWStr)] string pszURL, [MarshalAs(UnmanagedType.Bool)] out bool pfHasChildRule);
        [PreserveSig] int IncludedInCrawlScope([MarshalAs(UnmanagedType.LPWStr)] string pszURL, [MarshalAs(UnmanagedType.Bool)] out bool pfIsIncluded);
        [PreserveSig] int IncludedInCrawlScopeEx([MarshalAs(UnmanagedType.LPWStr)] string pszURL, [MarshalAs(UnmanagedType.Bool)] out bool pfIsIncluded, out int pReason);
        [PreserveSig] int RevertToDefaultScopes();
        [PreserveSig] int SaveAll();
        [PreserveSig] int GetParentScopeVersionId([MarshalAs(UnmanagedType.LPWStr)] string pszURL, out int plScopeId);
        [PreserveSig] int RemoveDefaultScopeRule([MarshalAs(UnmanagedType.LPWStr)] string pszURL);
    }

    [ComImport, Guid("AB310581-AC80-11D1-8DF3-00C04FB6EF69"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISearchManager {
        [PreserveSig] int GetIndexerVersionStr([MarshalAs(UnmanagedType.LPWStr)] out string ppszVersionString);
        [PreserveSig] int GetIndexerVersion(out uint pdwMajor, out uint pdwMinor);
        [PreserveSig] int GetParameter([MarshalAs(UnmanagedType.LPWStr)] string pszName, out IntPtr ppValue);
        [PreserveSig] int SetParameter([MarshalAs(UnmanagedType.LPWStr)] string pszName, IntPtr pValue);
        [PreserveSig] int get_ProxyName([MarshalAs(UnmanagedType.LPWStr)] out string ppszProxyName);
        [PreserveSig] int get_BypassList([MarshalAs(UnmanagedType.LPWStr)] out string ppszBypassList);
        [PreserveSig] int SetProxy(int sUseProxy, [MarshalAs(UnmanagedType.Bool)] bool fLocalByPassProxy, uint dwPortNumber, [MarshalAs(UnmanagedType.LPWStr)] string pszProxyName, [MarshalAs(UnmanagedType.LPWStr)] string pszByPassList);
        [PreserveSig] int GetCatalog([MarshalAs(UnmanagedType.LPWStr)] string pszCatalog, out ISearchCatalogManager ppCatalogManager);
    }

    public static class SearchApi {
        private static ISearchCrawlScopeManager GetScope() {
            var manager = (ISearchManager)new CSearchManager();
            ISearchCatalogManager catalog;
            int hr = manager.GetCatalog("SystemIndex", out catalog);
            if (hr != 0) {
                throw new COMException("ISearchManager.GetCatalog failed.", hr);
            }

            ISearchCrawlScopeManager scope;
            hr = catalog.GetCrawlScopeManager(out scope);
            if (hr != 0) {
                throw new COMException("ISearchCatalogManager.GetCrawlScopeManager failed.", hr);
            }

            return scope;
        }

        public static bool IsIncluded(string url) {
            bool included;
            int hr = GetScope().IncludedInCrawlScope(url, out included);
            if (hr != 0) {
                throw new COMException("ISearchCrawlScopeManager.IncludedInCrawlScope failed.", hr);
            }
            return included;
        }

        public static void Exclude(string url) {
            var scope = GetScope();
            int hr = scope.AddUserScopeRule(url, false, true, 0);
            if (hr != 0) {
                throw new COMException("ISearchCrawlScopeManager.AddUserScopeRule failed.", hr);
            }

            hr = scope.SaveAll();
            if (hr != 0) {
                throw new COMException("ISearchCrawlScopeManager.SaveAll failed.", hr);
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $code
}

function ConvertTo-STCWindowsSearchDriveRootUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter
    )

    $letter = $DriveLetter.ToUpperInvariant()
    return "file:///$letter`:\"
}

function Get-STCWindowsSearchWorkingSetRule {
    [CmdletBinding()]
    param()

    $rulePath = 'HKLM:\SOFTWARE\Microsoft\Windows Search\CrawlScopeManager\Windows\SystemIndex\WorkingSetRules'
    if (-not (Test-Path -LiteralPath $rulePath)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $rulePath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $props -or [string]::IsNullOrWhiteSpace([string] $props.URL)) {
            return
        }

        [pscustomobject]@{
            Key       = $_.PSChildName
            URL       = [string] $props.URL
            Include   = [int] $props.Include
            Default   = [int] $props.Default
            Suppress  = [int] $props.Suppress
            Policy    = [int] $props.Policy
            NoContent = [int] $props.NoContent
            Container = [int] $props.Container
        }
    })
}

function Test-STCWindowsSearchRuleExcludesDriveRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Rules,
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string] $DriveLetter
    )

    $letter = $DriveLetter.ToUpperInvariant()
    $rootPattern = "^file:///$letter`:(\\|/)(\[[^\]]+\](\\|/)?)?$"
    return [bool] @($Rules | Where-Object {
        $_.Include -eq 0 -and [string] $_.URL -match $rootPattern
    }).Count
}

function Get-STCWindowsSearchSamsungPolicyStatus {
    [CmdletBinding()]
    param()

    $drives = @(Get-SamsungTDrive)
    $rules = @(Get-STCWindowsSearchWorkingSetRule)
    $service = Get-Service -Name WSearch -ErrorAction SilentlyContinue

    $items = @()
    foreach ($drive in $drives) {
        $url = ConvertTo-STCWindowsSearchDriveRootUrl -DriveLetter $drive.DriveLetter
        $apiIncluded = $null
        $apiError = $null
        try {
            Initialize-STCWindowsSearchApi
            $apiIncluded = [STC.WindowsSearch.SearchApi]::IsIncluded($url)
        } catch {
            $apiError = $_.Exception.Message
        }

        $registryExcluded = Test-STCWindowsSearchRuleExcludesDriveRoot -Rules $rules -DriveLetter $drive.DriveLetter
        $excluded = ($apiIncluded -eq $false) -or $registryExcluded
        $items += [pscustomobject]@{
            Drive                  = $drive.Drive
            DriveLetter            = $drive.DriveLetter
            Model                  = $drive.Model
            Serial                 = $drive.Serial
            Root                   = $drive.Root
            SearchUrl              = $url
            WindowsSearchStatus    = if ($service) { [string] $service.Status } else { 'NotFound' }
            WindowsSearchStartType = if ($service) { [string] $service.StartType } else { 'NotFound' }
            ApiIncluded            = $apiIncluded
            ApiError               = $apiError
            RegistryExcluded       = $registryExcluded
            Excluded               = $excluded
            Action                 = if ($excluded) { 'AlreadyExcluded' } else { 'NeedsExclusion' }
        }
    }

    return @($items)
}

function Set-STCWindowsSearchSamsungExclusion {
    [CmdletBinding()]
    param()

    $before = @(Get-STCWindowsSearchSamsungPolicyStatus)
    $changes = @()
    foreach ($item in $before) {
        $errorMessage = $null
        $changed = $false
        if (-not $item.Excluded) {
            try {
                Initialize-STCWindowsSearchApi
                [STC.WindowsSearch.SearchApi]::Exclude($item.SearchUrl)
                $changed = $true
            } catch {
                $errorMessage = $_.Exception.Message
            }
        }

        $changes += [pscustomobject]@{
            Drive       = $item.Drive
            Model       = $item.Model
            Serial      = $item.Serial
            SearchUrl   = $item.SearchUrl
            WasExcluded = $item.Excluded
            Changed     = $changed
            Error       = $errorMessage
        }
    }

    $after = @(Get-STCWindowsSearchSamsungPolicyStatus)
    $result = [pscustomobject]@{
        Policy  = 'WindowsSearchSamsungDriveExclusion'
        Changed = [bool] @($changes | Where-Object { $_.Changed }).Count
        Changes = $changes
        Status  = $after
    }

    Write-STCLog -Category 'system-policy' -Message 'Windows Search Samsung drive exclusion applied.' -Data $result
    return $result
}
