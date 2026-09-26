#pragma once
// Required BEFORE any C++/WinRT header. Also pulls in combaseapi's DllCanUnloadNow declaration
// (HRESULT, no dllexport) that exports.cpp's definition must match.
#include <unknwn.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
// Persisting downloaded/in-memory fonts to ApplicationData LocalFolder and reading bundled assets.
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
// Remote @font-face CSS + font-file downloads.
#include <winrt/Windows.Web.Http.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <string>
#include <vector>
#include <sstream>
