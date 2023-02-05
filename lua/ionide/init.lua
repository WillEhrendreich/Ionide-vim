local vim = vim
local validate = vim.validate
local api = vim.api
local uc = vim.api.nvim_create_user_command
local lsp = vim.lsp
-- local log = require('vim.lsp.log')
-- local protocol = require('vim.lsp.protocol')
local tbl_extend = vim.tbl_extend

local function try_require(...)
  local status, lib = pcall(require, ...)
  if (status) then return lib end
  return nil
end

local M = {}
local callbacks = {}
M.CallBackResults = {}
M.workspace_folders = {}
M.Projects = {}
M.NvimSettings = {}
M.DefaultServerSettings = {}
M.DefaultLspConfig = {}
M.MergedConfig = {}
M.PassedInConfig = {}

local lspconfig_is_present = true
local util = try_require('lspconfig.util')
if util == nil then
  lspconfig_is_present = false
  util = require('ionide.util')
end

---@param fn function|nil See |lsp-handler|
---@returns int key
--- generates a key to look up the function call and assigns it to callbacks[newRandomIntKeyHere]
--- then returns the key it created
function M.RegisterCallback(fn)
  local rnd = os.time()
  callbacks[rnd] = fn
  M.CallBackResults[rnd] = fn
  return rnd
end

function M.ResolveCallback(key, arg)
  if callbacks[key] then
    local callback = callbacks[key]
    local result = callback(arg)
    if result then

      vim.inspect("result of callback with key of " .. key .. " is\n" .. vim.inspect(result))
    end
    callbacks[key] = nil
  else
    vim.inspect("no callback found in the Ionide callbacks collection with the key " .. key)

  end
end

--  function! s:PlainNotification(content)
--    return { 'Content': a:content }
-- endfunction

function M.PlainNotification(content)
  return { Content = content }
end

-- function! s:TextDocumentIdentifier(path)
--     let usr_ss_opt = &shellslash
--     set shellslash
--     let uri = fnamemodify(a:path, ":p")
--     if uri[0] == "/"
--         let uri = "file://" . uri
--     else
--         let uri = "file:///" . uri
--     endif
--     let &shellslash = usr_ss_opt
--     return { 'Uri': uri }
-- endfunction

function M.TextDocumentIdentifier(path)
  local usr_ss_opt = vim.o.shellslash
  vim.o.shellslash = true
  local uri = vim.fn.fnamemodify(path, ":p")
  if string.sub(uri, 1, 1) == '/' then
    uri = "file://" .. uri
  else
    uri = "file:///" .. uri
  end
  vim.o.shellslash = usr_ss_opt
  return { Uri = uri }
end

-- function! s:Position(line, character)
--     return { 'Line': a:line, 'Character': a:character }
-- endfunction

function M.Position(line, character)
  return { Line = line, Character = character }
end

-- function! s:TextDocumentPositionParams(documentUri, line, character)
--     return {
--         \ 'TextDocument': s:TextDocumentIdentifier(a:documentUri),
--         \ 'Position':     s:Position(a:line, a:character)
--         \ }
-- endfunction

function M.TextDocumentPositionParams(documentUri, line, character)
  return {
    TextDocument = M.TextDocumentIdentifier(documentUri),
    Position = M.Position(line, character)
  }
end

-- function! s:DocumentationForSymbolRequest(xmlSig, assembly)
--     return {
--         \ 'XmlSig': a:xmlSig,
--         \ 'Assembly': a:assembly
--         \ }
-- endfunction

function M.DocumentationForSymbolRequest(xmlSig, assembly)
  return {
    XmlSig = xmlSig,
    Assembly = assembly
  }
end

-- function! s:ProjectParms(projectUri)
--     return { 'Project': s:TextDocumentIdentifier(a:projectUri) }
-- endfunction

function M.ProjectParms(projectUri)
  return {
    Project = M.TextDocumentIdentifier(projectUri),
  }
end

-- function! s:WorkspacePeekRequest(directory, deep, excludedDirs)
--     return {
--         \ 'Directory': fnamemodify(a:directory, ":p"),
--         \ 'Deep': a:deep,
--         \ 'ExcludedDirs': a:excludedDirs
--         \ }
-- endfunction


function M.WorkspacePeekRequest(directory, deep, excludedDirs)
  return {
    Directory = string.gsub(directory, '\\', '/'),
    Deep = deep,
    ExcludedDirs = excludedDirs
  }
end

-- function! s:FsdnRequest(query)
--     return { 'Query': a:query }
-- endfunction

function M.FsdnRequest(query)
  return { Query = query }
end

-- function! s:WorkspaceLoadParms(files)
--     let prm = []
--     for file in a:files
--         call add(prm, s:TextDocumentIdentifier(file))
--     endfor
--     return { 'TextDocuments': prm }
-- endfunction

function M.WorkspaceLoadParms(files)
  local prm = {}
  for _, file in ipairs(files) do
    table.insert(prm, M.TextDocumentIdentifier(file))
  end
  return { TextDocuments = prm }
end

local function toSnakeCase(str)
  local snake = str:gsub("%u", function(ch) return "_" .. ch:lower() end)
  return snake:gsub("^_", "")
end

local function buildConfigKeys(camels)
  local keys = {}
  for _, c in ipairs(camels) do
    local key =
    function()
      if c.default then
        return {
          snake = toSnakeCase(c.key),
          camel = c.key,
          default = c.default
        }
      else
        return {
          snake = toSnakeCase(c.key),
          camel = c.key,
        }
      end
    end
    table.insert(keys, key())
  end
  return keys
end

function M.Call(method, params, callback_key)
  if not callbacks[callback_key] then

    callback_key = M.RegisterCallback(method)

  end
  local handler = function(err, result, ctx, _)
    vim.notify("result is: " .. vim.inspect({
      result = vim.inspect(result or "NO result"),
      err = vim.inspect(err or "NO err"),
      client_id = vim.inspect(ctx.client_id or "NO ctx clientid  "),
      bufnr = vim.inspect(ctx.bufnr or "NO ctx clientid  ")
    }))
    if result ~= nil then
      vim.notify("result is: " .. vim.inspect(result))
      M.ResolveCallback(callback_key, {
        result = result,
        err = err,
        client_id = ctx.client_id,
        bufnr = ctx.bufnr
      })
    end
  end
  -- if method == "fsharp/compilerLocation" then
  vim.notify("requesting method called '" ..
    vim.pretty_print(vim.inspect(method)) ..
    "' with params of " .. vim.inspect(params or " NO PARAMS Given ") .. " with callback key of: " .. callback_key)
  -- end
  ---@returns 2-tuple:
  ---  - Map of client-id:request-id pairs for all successful requests.
  ---  - Function which can be used to cancel all the requests. You could instead
  ---    iterate all clients and call their `cancel_request()` methods.
  -- function lsp.buf_request(bufnr, method, params, handler)
  local request = lsp.buf_request(0, method, params, handler)
  if request then
    vim.notify("request gave : " .. vim.pretty_print(vim.inspect(request)))
    if callbacks[callback_key] then
      vim.notify("request was found in callbacks: " .. vim.inspect(callbacks[callback_key]))
    end
  end
end

function M.Notify(method, params)
  lsp.buf_notify(0, method, params)
end

function M.Signature(filePath, line, character, cont)
  return M.Call('fsharp/signature', M.TextDocumentPositionParams(filePath, line, character),
    cont)
end

function M.SignatureData(filePath, line, character, cont)
  return M.Call('fsharp/signatureData', M.TextDocumentPositionParams(filePath, line, character)
    , cont)
end

function M.LineLens(projectPath, cont)
  return M.Call('fsharp/lineLens', M.ProjectParms(projectPath), cont)
end

function M.CompilerLocation(cont)
  return M.Call('fsharp/compilerLocation', {}, cont)
end

uc('IonideCompilerLocation',
  function()
    -- local cb = M.RegisterCallback(M.CompilerLocation)
    -- local rcb = M.ResolveCallback(cb,{})
    -- vim.notify(vim.inspect(rcb()))
    local key = os.time()
    vim.notify("Calling for CompilerLocations with timekey of " .. vim.inspect(key))
    M.Call('fsharp/compilerLocation', {}, key)
    -- M.CompilerLocation(key)
    -- vim.notify(vim.inspect(M.Call('fsharp/compilerLocation', {}, os.time())))
  end
  , { nargs = 0, desc = "Get compiler location data from FSAC" })

function M.Compile(projectPath, cont)
  return M.Call('fsharp/compile', M.ProjectParms(projectPath), cont)
end

function M.WorkspacePeek(directory, depth, excludedDirs, cont)
  return M.Call('fsharp/workspacePeek', M.WorkspacePeekRequest(directory, depth, excludedDirs),
    cont)
end

function M.WorkspaceLoad(files, cont)
  return M.Call('fsharp/workspaceLoad', M.WorkspaceLoadParms(files), cont)
end

function M.Project(projectPath, cont)
  return M.Call('fsharp/project', M.ProjectParms(projectPath), cont)
end

function M.Fsdn(signature, cont)
  return M.Call('fsharp/fsdn', M.FsdnRequest(signature), cont)
end

function M.F1Help(filePath, line, character, cont)
  return M.Call('fsharp/f1Help', M.TextDocumentPositionParams(filePath, line, character), cont)
end

function M.Documentation(filePath, line, character, cont)
  return M.Call('fsharp/documentation', M.TextDocumentPositionParams(filePath, line, character)
    , cont)
end

function M.DocumentationSymbol(xmlSig, assembly, cont)
  return M.Call('fsharp/documentationSymbol', M.DocumentationForSymbolRequest(xmlSig, assembly)
    , cont)
end

-- from https://github.com/fsharp/FsAutoComplete/blob/main/src/FsAutoComplete/LspHelpers.fs
-- FSharpConfigDto =
--   { AutomaticWorkspaceInit: bool option
--     WorkspaceModePeekDeepLevel: int option
--     ExcludeProjectDirectories: string[] option
--     KeywordsAutocomplete: bool option
--     ExternalAutocomplete: bool option
--     Linter: bool option
--     LinterConfig: string option
--     IndentationSize: int option
--     UnionCaseStubGeneration: bool option
--     UnionCaseStubGenerationBody: string option
--     RecordStubGeneration: bool option
--     RecordStubGenerationBody: string option
--     InterfaceStubGeneration: bool option
--     InterfaceStubGenerationObjectIdentifier: string option
--     InterfaceStubGenerationMethodBody: string option
--     UnusedOpensAnalyzer: bool option
--     UnusedDeclarationsAnalyzer: bool option
--     SimplifyNameAnalyzer: bool option
--     ResolveNamespaces: bool option
--     EnableReferenceCodeLens: bool option
--     EnableAnalyzers: bool option
--     AnalyzersPath: string[] option
--     DisableInMemoryProjectReferences: bool option
--     LineLens: LineLensConfig option
--     UseSdkScripts: bool option
--     DotNetRoot: string option
--     FSIExtraParameters: string[] option
--     FSICompilerToolLocations: string[] option
--     TooltipMode: string option
--     GenerateBinlog: bool option
--     AbstractClassStubGeneration: bool option
--     AbstractClassStubGenerationObjectIdentifier: string option
--     AbstractClassStubGenerationMethodBody: string option
--     CodeLenses: CodeLensConfigDto option
--     InlayHints: InlayHintDto option
--     Debug: DebugDto option }
--
-- type FSharpConfigRequest = { FSharp: FSharpConfigDto }



function M.LoadDefaultServerSettings()
  local FSharpSettings = {}
  local camels = {
    --   { AutomaticWorkspaceInit: bool option
    --AutomaticWorkspaceInit = false
    { key = "AutomaticWorkspaceInit", default = true },
    --     WorkspaceModePeekDeepLevel: int option
    --WorkspaceModePeekDeepLevel = 2
    { key = "WorkspaceModePeekDeepLevel", default = 4 },
    --     ExcludeProjectDirectories: string[] option
    -- = [||]
    { key = "ExcludeProjectDirectories", default = {} },
    --     KeywordsAutocomplete: bool option
    -- false
    { key = "keywordsAutocomplete", default = true },
    --     ExternalAutocomplete: bool option
    --false
    { key = "ExternalAutocomplete", default = false },
    --     Linter: bool option
    --false
    { key = "Linter", default = true },
    --     IndentationSize: int option
    --4
    { key = "IndentationSize", default = 2 },
    --     UnionCaseStubGeneration: bool option
    --false
    { key = "UnionCaseStubGeneration", default = true },
    --     UnionCaseStubGenerationBody: string option
    --    """failwith "Not Implemented" """
    { key = "UnionCaseStubGenerationBody", default = "failwith \"Not Implemented\"" },
    --     RecordStubGeneration: bool option
    --false
    { key = "RecordStubGeneration", default = true },
    --     RecordStubGenerationBody: string option
    -- "failwith \"Not Implemented\""
    { key = "RecordStubGenerationBody", default = "failwith \"Not Implemented\"" },
    --     InterfaceStubGeneration: bool option
    --false
    { key = "InterfaceStubGeneration", default = true },
    --     InterfaceStubGenerationObjectIdentifier: string option
    -- "this"
    { key = "InterfaceStubGenerationObjectIdentifier", default = "this" },
    --     InterfaceStubGenerationMethodBody: string option
    -- "failwith \"Not Implemented\""
    { key = "InterfaceStubGenerationMethodBody", default = "failwith \"Not Implemented\"" },
    --     UnusedOpensAnalyzer: bool option
    --false
    { key = "UnusedOpensAnalyzer", default = true },
    --     UnusedDeclarationsAnalyzer: bool option
    --false
    --
    { key = "UnusedDeclarationsAnalyzer", default = true },
    --     SimplifyNameAnalyzer: bool option
    --false
    --
    { key = "SimplifyNameAnalyzer", default = true },
    --     ResolveNamespaces: bool option
    --false
    --
    { key = "ResolveNamespaces", default = true },
    --     EnableReferenceCodeLens: bool option
    --false
    --
    { key = "EnableReferenceCodeLens", default = true },
    --     EnableAnalyzers: bool option
    --false
    --
    { key = "EnableAnalyzers", default = true },
    --     AnalyzersPath: string[] option
    --
    { key = "AnalyzersPath", default = {} },
    --     DisableInMemoryProjectReferences: bool option
    --false|
    --
    { key = "DisableInMemoryProjectReferences", default = false },
    --     LineLens: LineLensConfig option
    --
    { key = "LineLens", default = { enabled = "always", prefix = "//" } },
    --     UseSdkScripts: bool option
    --false
    --
    { key = "UseSdkScripts", default = true },
    --     DotNetRoot: string option  Environment.dotnetSDKRoot.Value.FullName
    --
    { key = "dotNetRoot", default =

    (function()
      local function find_executable(name)
        local path = os.getenv("PATH") or ""
        for dir in string.gmatch(path, "[^:]+") do
          local executable = dir .. "/" .. name .. ".exe"
          if os.execute("test -x " .. executable) == 1 then
            return dir .. "/"
          end
        end
        return nil
      end

      local dnr = os.getenv("DOTNET_ROOT")
      if dnr and not dnr == "" then
        return dnr
      else
        if vim.fn.has("win32") then
          local canExecute = vim.fn.executable("dotnet") == 1
          if not canExecute then
            local vs1 = vim.fs.find({ "fscAnyCpu.exe" },
              { path = "C:/Program Files/Microsoft Visual Studio", type = "file" })
            local vs2 = vim.fs.find({ "fscAnyCpu.exe" },
              { path = "C:/Program Files (x86)/Microsoft Visual Studio", type = "file" })
            return vs1 or vs2 or ""
          else
            local dn = vim.fs.find({ "dotnet.exe" }, { path = "C:/Program Files/dotnet/", type = "file" })
            return dn or find_executable("dotnet") or ""
          end
        else
          return ""
        end
        return ""
      end
    end)()
    },

    --     FSIExtraParameters: string[] option
    --     j
    { key = "fsiExtraParameters", default = {} },
    --     FSICompilerToolLocations: string[] option
    --
    { key = "fsiCompilerToolLocations", default = {} },
    --     TooltipMode: string option
    --TooltipMode = "full"
    { key = "TooltipMode", default = "full" },
    --     GenerateBinlog: bool option
    -- GenerateBinlog = false
    { key = "GenerateBinlog", default = false },
    --     AbstractClassStubGeneration: bool option
    -- AbstractClassStubGeneration = true
    { key = "AbstractClassStubGeneration", default = true },
    --     AbstractClassStubGenerationObjectIdentifier: string option
    -- AbstractClassStubGenerationObjectIdentifier = "this"
    { key = "AbstractClassStubGenerationObjectIdentifier", default = "this" },
    --     AbstractClassStubGenerationMethodBody: string option, default = "failwith \"Not Implemented\""
    -- AbstractClassStubGenerationMethodBody = "failwith \"Not Implemented\""
    --
    { key = "AbstractClassStubGenerationMethodBody", default = "failwith \"Not Implemented\"" },
    --     CodeLenses: CodeLensConfigDto option
    --  type CodeLensConfigDto =
    -- { Signature: {| Enabled: bool option |} option
    --   References: {| Enabled: bool option |} option }
    { key = "CodeLenses",
      default = {
        Signature = { Enabled = true },
        References = { Enabled = true },
      },
    },
    --     InlayHints: InlayHintDto option
    --type InlayHintsConfig =
    -- { typeAnnotations: bool
    -- parameterNames: bool
    -- disableLongTooltip: bool }
    -- static member Default =
    --   { typeAnnotations = true
    --     parameterNames = true
    --     disableLongTooltip = true }

    { key = "InlayHints",
      default = {
        typeAnnotations = true,
        parameterNames = true,
        disableLongTooltip = false,
      },
    },

    --     Debug: DebugDto option }
    --   type DebugConfig =
    -- { DontCheckRelatedFiles: bool
    --   CheckFileDebouncerTimeout: int
    --   LogDurationBetweenCheckFiles: bool
    --   LogCheckFileDuration: bool }
    --
    -- static member Default =
    --   { DontCheckRelatedFiles = false
    --     CheckFileDebouncerTimeout = 250
    --     LogDurationBetweenCheckFiles = false
    --     LogCheckFileDuration = false }
    --       }
    { key = "Debug",
      default =
      { DontCheckRelatedFiles = false,
        CheckFileDebouncerTimeout = 250,
        LogDurationBetweenCheckFiles = false,
        LogCheckFileDuration = false,
      },
    },

  }

  if M.UseRecommendedServerConfig == true then vim.notify("[Ionide] - UseRecommendedServerConfig was true. All settings set to defaults.  ") end
  local keys = buildConfigKeys(camels)
  for _, key in ipairs(keys) do

    -- if not M[key.snake] then
    -- M[key.snake] = key.default
    -- end

    -- if not M[key.camel] then M[key.camel] = key.default end
    -- if not M.Configs[key.camel] then M.Configs[key.camel] = key.default end
    -- if not vim.g[key.snake] then
    --   vim.g[key.snake] = key.default or ""
    -- end
    if not FSharpSettings[key.camel] then
      FSharpSettings[key.camel] = key.default
    end
    -- if vim.g["fsharp#" .. key.snake] then
    -- config[key.camel] = vim.g["fsharp#" .. key.snake]
    -- M.Configs[key.camel] = vim.g["fsharp#" .. key.snake]
    -- elseif vim.g["fsharp#" .. key.camel] then
    -- config[key.camel] = vim.g["fsharp#" .. key.camel]
    -- M.Configs[key.camel] = vim.g["fsharp#" .. key.camel]
    if key.default and M.UseRecommendedServerConfig then
      -- vim.g["fsharp#" .. key.camel] = key.default
      -- vim.g["fsharp#" .. key.snake] = key.default
      FSharpSettings[key.camel] = key.default
      -- M.Configs[key.camel] = key.default
    end
  end
  -- vim.notify("ionide config is " .. vim.inspect(config))
  return FSharpSettings
end

function M.UpdateServerConfig(newSettingsTable)

  --  local input = vim.fn.input({ prompt = "Attach your debugger, to process " .. vim.inspect(vim.fn.getpid()) })
  local n = newSettingsTable or M.PassedInConfig["settings"].FSharp or {}
  local defaults = M.DefaultServerSettings
  local mergedSettings = vim.tbl_deep_extend("keep", n, defaults)
  local oldMergedSettings = M.MergedConfig.settings
  -- vim.notify("ionide config is " .. vim.inspect(fsharp))
  if not M.PassedInConfig["settings"] then
    M.PassedInConfig["settings"] = { FSharp = mergedSettings }
  else
    local newPassedIn = vim.tbl_deep_extend("keep", { FSharp = mergedSettings }, oldMergedSettings)
    M.PassedInConfig["settings"] = newPassedIn
  end
  local settings = { settings = { FSharp = mergedSettings } }
  local mergedConfig = vim.tbl_deep_extend("keep", M.PassedInConfig, M.MergedConfig)
  M.MergedConfig = mergedConfig
  M.Notify("workspace/didChangeConfiguration", settings)
end

function M.AddThenSort(value, tbl)
  if not vim.tbl_contains(tbl, value) then
    table.insert(tbl, value)
    -- table.sort(tbl)
  end
  -- print("after sorting table, it now looks like this : " .. vim.inspect(tbl))
  return tbl
end

--see: https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_documentHighlight
function M.HandleDocumentHighlight(range, _)
  local u = require("vim.lsp.util")
  u.buf_highlight_references(0, range or {}, "utf-16")
end

function M.HandleNotifyWorkspace(payload)
  -- vim.notify("handling notifyWorkspace")
  local content = vim.json.decode(payload.content)
  if content then
    if content.Kind == 'projectLoading' then
      -- vim.notify("[Ionide] Loading " .. content.Data.Project)
      -- print("[Ionide] now calling AddOrUpdateThenSort on table  " .. vim.inspect(Workspace))
      M.Projects = M.AddThenSort(content.Data.Project, M.Projects)
      local dir = vim.fs.dirname(content.Data.Project)
      M.workspace_folders = M.AddThenSort(dir, M.workspace_folders)
      -- print("after attempting to reassign table value it looks like this : " .. vim.inspect(Workspace))
    elseif content.Kind == 'workspaceLoad' and content.Data.Status == 'finished' then
      -- print("[Ionide] calling updateServerConfig ... ")
      -- print("[Ionide] before calling updateServerconfig, workspace looks like:   " .. vim.inspect(Workspace))
      M.UpdateServerConfig()
      -- print("[Ionide] after calling updateServerconfig, workspace looks like:   " .. vim.inspect(Workspace))
      if #M.Projects > 0 then
        if #M.Projects > 1 then
          vim.notify("[Ionide] Workspace loaded " ..
            #M.Projects .. " projects:\n" .. vim.inspect(M.Projects))
        else
          vim.notify("[Ionide] Workspace loaded project:\n" .. vim.inspect(M.Projects))
        end
      else
        vim.notify("[Ionide] Workspace is empty! Something went wrong. ")
      end
    end
  end
end

function M.HandleCompilerLocation(result)
  vim.notify("handling compilerLocation response\n" ..
    "result is: \n" .. vim.inspect(result or "Nothing came back from the server.."))
  -- vim.notify("handling compilerLocation response\n" .. "result is: \n" .. vim.inspect(vim.json.decode(result.content) or "Nothing came back from the server.."))
  -- local content = vim.json.decode(payload.content)
  -- if content then

  -- vim.notify(vim.inspect(content))
  -- if content.Kind == 'projectLoading' then
  --   print("[Ionide] Loading " .. content.Data.Project)
  --   -- print("[Ionide] now calling AddOrUpdateThenSort on table  " .. vim.inspect(Workspace))
  --   Workspace = addThenSort(content.Data.Project, Workspace)
  --   -- print("after attempting to reassign table value it looks like this : " .. vim.inspect(Workspace))
  -- elseif content.Kind == 'workspaceLoad' and content.Data.Status == 'finished' then
  --   print("[Ionide] calling updateServerConfig ... ")
  --   -- print("[Ionide] before calling updateServerconfig, workspace looks like:   " .. vim.inspect(Workspace))
  --   M.UpdateServerConfig()
  --   -- print("[Ionide] after calling updateServerconfig, workspace looks like:   " .. vim.inspect(Workspace))
  --   print("[Ionide] Workspace loaded (" .. #Workspace .. " project(s))")
  -- end
  -- end
end

local handlers = {
  ['fsharp/notifyWorkspace'] = "HandleNotifyWorkspace",
  ['textDocument/documentHighlight'] = "HandleDocumentHighlight",
  ['fsharp/compilerLocation'] = "HandleCompilerLocation"
}

local function GetHandlers()
  return handlers
end

function M.CreateHandlers()

  local h = GetHandlers()
  local r = {}
  for method, func_name in pairs(h) do
    local handler = function(err, params, ctx, _config)
      -- local handler = function(_, params, _, _)

      if func_name == "HandleCompilerLocation" then
        vim.notify("handling compiler location request, here are the params \n" ..
          vim.inspect({ err or "", params or "", ctx or "", _config or "" }))
      end

      -- if err then
      --   -- LSP spec:
      --   -- interface ResponseError:
      --   --  code: integer;
      --   --  message: string;
      --   --  data?: string | number | boolean | array | object | null;
      --   -- Per LSP, don't show ContentModified error to the user.
      --   if err.code ~= protocol.ErrorCodes.ContentModified and func_name then
      --
      --     local client = vim.lsp.get_client_by_id(ctx.client_id)
      --     local client_name = client and client.name or string.format('client_id=%d', ctx.client_id)
      --
      --     err_message(client_name .. ': ' .. tostring(err.code) .. ': ' .. err.message)
      --   end
      --   return
      -- end

      -- if params == nil or not (method == ctx.method) then return end
      M[func_name](params)
    end

    r[method] = handler
  end
  M.Handlers = r
  return r
end

local function load(arg)
  M.WorkspaceLoad(arg, nil)
end

function M.LoadProject(...)
  local prjs = {}
  for _, proj in ipairs({ ... }) do
    table.insert(prjs, util.fnamemodify(proj, ':p'))
  end
  load(prjs)
end

function M.ShowLoadedProjects()
  for _, proj in ipairs(M.workspace_folders) do
    print("- " .. proj)
  end
end

function M.ReloadProjects()
  print("[Ionide] Reloading Projects")
  if #M.workspace_folders > 0 then
    M.WorkspaceLoad(M.workspace_folders, nil)
  else
    print("[Ionide] Workspace is empty")
  end
end

function M.OnFSProjSave()
  if vim.bo.ft == "fsharp_project" and M.AutomaticReloadWorkspace and M.AutomaticReloadWorkspace == true then
    vim.notify("fsharp project saved, reloading...")
    M.ReloadProjects()
  end
end

function M.ShowConfigsFromServerRequest()
  M.Call("workspace/workspaceFolders", {})
end

function M.ShowConfigs()
  vim.inspect(M.MergedConfig)
end

-- Parameters: ~
--   • {name}     Name of the new user command. Must begin with an uppercase
--                letter.
--   • {command}  Replacement command to execute when this user command is
--                executed. When called from Lua, the command can also be a
--                Lua function. The function is called with a single table
--                argument that contains the following keys:
--                • name: (string) Command name
--                • args: (string) The args passed to the command, if any
--                  |<args>|
--                • fargs: (table) The args split by unescaped whitespace
--                  (when more than one argument is allowed), if any
--                  |<f-args>|
--                • bang: (boolean) "true" if the command was executed with a
--                  ! modifier |<bang>|
--                • line1: (number) The starting line of the command range
--                  |<line1>|
--                • line2: (number) The final line of the command range
--                  |<line2>|
--                • range: (number) The number of items in the command range:
--                  0, 1, or 2 |<range>|
--                • count: (number) Any count supplied |<count>|
--                • reg: (string) The optional register, if specified |<reg>|
--                • mods: (string) Command modifiers, if any |<mods>|
--                • smods: (table) Command modifiers in a structured format.
--                  Has the same structure as the "mods" key of
--                  |nvim_parse_cmd()|.
--   • {opts}     Optional command attributes. See |command-attributes| for
--                more details. To use boolean attributes (such as
--                |:command-bang| or |:command-bar|) set the value to "true".
--                In addition to the string options listed in
--                |:command-complete|, the "complete" key also accepts a Lua
--                function which works like the "customlist" completion mode
--                |:command-completion-customlist|. Additional parameters:
--                • desc: (string) Used for listing the command when a Lua
--                  function is used for {command}.
--                • force: (boolean, default true) Override any previous
--                  definition.
--                • preview: (function) Preview callback for 'inccommand'
--                  |:command-preview|
uc("IonideShowConfigs", M.ShowConfigs, {})


function M.LoadNvimSettings()
  local result = {}
  local s = {
    FsautocompleteCommand = { "fsautocomplete", "--adaptive-lsp-server-enabled", "-v" },
    UseRecommendedServerConfig = false,
    AutomaticWorkspaceInit = true,
    AutomaticReloadWorkspace = true,
    ShowSignatureOnCursorMove = true,
    FsiCommand =

    (function()

      local function determineFsiPath(useNetCore, ifNetFXUseAnyCpu)
        local pf, exe, arg, fsiExe
        if useNetCore == true then
          pf = os.getenv("ProgramW6432")
          if pf == nil or pf == "" then
            pf = os.getenv("ProgramFiles")
          end
          exe = pf .. "/dotnet/dotnet.exe"
          arg = "fsi"
          if not os.rename(exe, exe) then
            vim.notify("Could Not Find fsi.exe: " .. exe)
          end
          return exe .. " " .. arg
        else
          local function fsiExeName()
            local any = ifNetFXUseAnyCpu or true
            if any then
              return "fsiAnyCpu.exe"
              -- elseif runtime.architecture == "Arm64" then
              --   return "fsiArm64.exe"
            else
              return "fsi.exe"
            end
          end

          -- - path (string): Path to begin searching from. If
          --        omitted, the |current-directory| is used.
          -- - upward (boolean, default false): If true, search
          --          upward through parent directories. Otherwise,
          --          search through child directories
          --          (recursively).
          -- - stop (string): Stop searching when this directory is
          --        reached. The directory itself is not searched.
          -- - type (string): Find only files ("file") or
          --        directories ("directory"). If omitted, both
          --        files and directories that match {names} are
          --        included.
          -- - limit (number, default 1): Stop the search after
          --         finding this many matches. Use `math.huge` to
          --         place no limit on the number of matches.

          local function determineFsiRelativePath(name)
            local find = vim.fs.find({ name },
              { path = vim.fn.expand("%:h"), upward = false, type = "file", limit = 1 })
            if vim.tbl_isempty(find) then
              return ""
            else
              return find
            end
          end

          local name = fsiExeName()
          local path = determineFsiRelativePath(name)
          if not path == "" then
            fsiExe = path
          else
            local fsbin = os.getenv("FSharpBinFolder")
            if fsbin == nil or fsbin == "" then
              local lastDitchEffortPath =
              vim.fs.find({ name },
                { path = "C:/Program Files (x86)/Microsoft Visual Studio/", upward = false, type = "file", limit = 1 })
              if not lastDitchEffortPath then
                fsiExe = "Could not find FSI"
              else
                fsiExe = lastDitchEffortPath
              end
            else
              fsiExe = fsbin .. "/Tools/" .. name
            end
          end
          return fsiExe
        end
      end

      local function shouldUseAnyCpu()
        local uname = vim.api.nvim_call_function("system", { "uname -m" })
        local architecture = uname:gsub("\n", "")
        if architecture == "" then
          local output = vim.api.nvim_call_function("system", { "cmd /c echo %PROCESSOR_ARCHITECTURE%" })
          architecture = output:gsub("\n", "")
        end
        if string.match(architecture, "64") then
          return true
        else
          return false
        end
      end

      local useSdkScripts = false
      if M.PassedInConfig.Settings then
        if M.PassedInConfig.Settings.FSharp then
          if M.PassedInConfig.Settings.FSharp.UseSdkScripts then
            useSdkScripts = M.PassedInConfig.Settings.FSharp.UseSdkScripts
          end
        end
      end

      if M.DefaultServerSettings then
        local ds = M.DefaultServerSettings
        if ds.UseSdkScripts then
          useSdkScripts = ds.UseSdkScripts
        end
      end
      local useAnyCpu = shouldUseAnyCpu()
      return determineFsiPath(useSdkScripts, useAnyCpu)
    end)(),
    FsiKeymap = "vscode",
    FsiWindowCommand = "botright 10new",
    FsiFocusOnSend = false,
    LspAutoSetup = false,
    LspRecommendedColorscheme = true,
    LspCodelens = true,
    FsiVscodeKeymaps = true,
    Statusline = "Ionide",
    AutocmdEvents = { "BufEnter", "BufWritePost", "CursorHold", "CursorHoldI", "InsertEnter", "InsertLeave" },
    FsiKeymapSend = "<M-cr>",
    FsiKeymapToggle = "<M-@>",

  }
  -- for key, v in pairs(generalConfigs) do
  for k, v in pairs(s) do
    -- local k = toSnakeCase(key)
    -- if not vim.g["fsharp#" .. k] then
    -- vim.g["fsharp#" .. k] = v
    -- end
    if not result[k] then result[k] = v end
    -- if not M.Configs[k] then M.Configs[k] = v end
  end


  return result
end

-- function! fsharp#showSignature()
--     function! s:callback_showSignature(result)
--         let result = a:result
--         if exists('result.result.content')
--             let content = json_decode(result.result.content)
--             if exists('content.Data')
--                 echo substitute(content.Data, '\n\+$', ' ', 'g')
--             endif
--         endif
--     endfunction
--     call s:signature(expand('%:p'), line('.') - 1, col('.') - 1, function("s:callback_showSignature"))
-- endfunction


function M.ShowSignature()
  local cbShowSignature = function(result)
    if result then
      if result.result then
        if result.result.content then
          local content = vim.json.decode(result.result.content)
          if content then
            if content.Data then
              -- Using gsub() instead of substitute() in Lua
              -- and % instead of :
              print(content.Data:gsub("\n+$", " "))
            end
          end
        end
      end
    end
  end

  M.Signature(vim.fn.expand("%:p"), vim.cmd.line('.') - 1, vim.cmd.col('.') - 1,
    cbShowSignature)
end

-- function! fsharp#OnCursorMove()
--     if g:fsharp#show_signature_on_cursor_move
--         call fsharp#showSignature()
--     endif
-- endfunction
--
function M.OnCursorMove()
  if M.ShowSignatureOnCursorMove then
    M.ShowSignature()
  end
end

function M.RegisterAutocmds()
  if (M.LspCodelens == true or M.LspCodelens == 1) then
    local autocmd = vim.api.nvim_create_autocmd
    local grp = vim.api.nvim_create_augroup


    autocmd({ "CursorHold,InsertLeave" }, {
      desc = "FSharp Auto refresh code lens ",
      group = grp("FSharp_AutoRefreshCodeLens", { clear = true }),
      pattern = "*.fs,*.fsi,*.fsx",
      callback = function() vim.lsp.codelens.refresh() end,
    })

    autocmd({ "CursorHold,InsertLeave" }, {
      desc = "URL Highlighting",
      group = grp("FSharp_AutoRefreshCodeLens", { clear = true }),
      pattern = "*.fs,*.fsi,*.fsx",
      callback = M.OnCursorMove(),
    })
  end
end

function M.Initialize()
  if not vim.fn.has("nvim") then
    print 'WARNING - This version of Ionide is only for NeoVim. please try Ionide/Ionide-Vim instead. '
    return
  end

  print 'Ionide Initializing'
  print 'Ionide calling updateServerConfig...'
  M.UpdateServerConfig()
  print 'Ionide calling SetKeymaps...'
  M.SetKeymaps()
  print 'Ionide calling registerAutocmds...'
  M.RegisterAutocmds()
  print 'Ionide Initialized'
end

function M.GitFirstRootDir(n)
  local root
  root = util.find_git_ancestor(n)
  root = root or util.root_pattern("*.sln")(n)
  root = root or util.root_pattern("*.fsproj")(n)
  root = root or util.root_pattern("*.fsx")(n)
  return root
end

function M.GetDefaultLspConfig()
  local nvimSettings = M.NvimSettings or {}
  local serverSettings = M.DefaultServerSettings
  local result = {
    name = "ionide",
    cmd = nvimSettings.FsautocompleteCommand,
    -- cmd ={ 'fsautocomplete', '--adaptive-lsp-server-enabled', '-v' },
    -- cmd_env = { DOTNET_ROLL_FORWARD = "LatestMajor" },
    cmd_env = nvimSettings.cmdEnv or { DOTNET_ROLL_FORWARD = "LatestMajor" },
    filetypes = { "fsharp", "fsharp_project" },
    autostart = true,
    handlers = M.CreateHandlers(),
    init_options = { AutomaticWorkspaceInit = nvimSettings.AutomaticWorkspaceInit },
    on_init = M.Initialize,
    settings = { FSharp = serverSettings },
    -- root_dir = local_root_dir,
    root_dir = util.root_pattern("*.sln"),
  }
  -- vim.notify("ionide default settings are : " .. vim.inspect(result))
  return result
end

M.Manager = nil
function M.AutoStartIfNeeded(m, config)
  local auto_setup = (M.NvimSettings.LspAutoSetup == 1)
  if auto_setup and not (config.autostart == false) then
    m.autostart()
  end
end

function M.DelegateToLspConfig(config)
  local lspconfig = require('lspconfig')
  local configs = require('lspconfig.configs')
  if not (configs['ionide']) then
    configs['ionide'] = {
      default_config = M.DefaultLspConfig,
      docs = {
        description = [[ https://github.com/willehrendreich/Ionide-vim ]],
      },
    }
  end
  lspconfig.ionide.setup(config)
end

--- ftplugin section ---
vim.filetype.add(
  {
    extension = {
      fsproj = function(_, _)
        return 'fsharp_project', function(bufnr)
          vim.bo[bufnr].syn = "xml"
          vim.bo[bufnr].ro = false
          vim.b[bufnr].readonly = false
          vim.bo[bufnr].commentstring = "<!--%s-->"
          -- vim.bo[bufnr].comments = "<!--,e:-->"
          vim.opt_local.foldlevelstart = 99
          vim.w.fdm = 'syntax'
        end
      end,
    },
  })

vim.filetype.add(
  {
    extension = {
      fs = function(_, _)
        return 'fsharp', function(bufnr)

          if not vim.g.filetype_fs then
            vim.g['filetype_fs'] = 'fsharp'
          end
          if not vim.g.filetype_fs == 'fsharp' then
            vim.g['filetype_fs'] = 'fsharp'
          end
          -- if vim.b.did_fsharp_ftplugin and vim.b.did_fsharp_ftplugin == 1 then
          -- return
          -- end

          -- vim.b.did_fsharp_ftplugin = 1

          -- local cpo_save = vim.o.cpo
          -- vim.o.cpo = ''
          --
          -- enable syntax based folding
          vim.w.fdm = 'syntax'

          -- comment settings
          vim.bo[bufnr].formatoptions = 'croql'
          vim.bo[bufnr].commentstring = '(*%s*)'
          vim.bo[bufnr].comments = [[s0:*\ -,m0:*\ \ ,ex0:*),s1:(*,mb:*,ex:*),:\/\/\/,:\/\/]]

          -- make ftplugin undo-able
          -- vim.bo[bufnr].undo_ftplugin = 'setl fo< cms< com< fdm<'

          -- local function prompt(msg)
          --   local height = vim.o.cmdheight
          --   if height < 2 then
          --     vim.o.cmdheight = 2
          --   end
          --   print(msg)
          --   vim.o.cmdheight = height
          -- end

          -- vim.o.cpo = cpo_save

        end
      end,
    },
  })

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.fsproj",
  desc = "FSharp Auto refresh on project save",
  group = vim.api.nvim_create_augroup("FSharpLCFsProj", { clear = true }),
  callback = function() M.OnFSProjSave() end
})

-- vim.api.nvim_create_autocmd("BufWritePost", {
--   pattern = "*.fsproj",
--   desc = "FSharp Auto refresh on project save",
--   group = vim.api.nvim_create_augroup("FSharpLCFsProj", { clear = true }),
--   callback = function() M.OnFSProjSave() end
-- })

--augroup FSharpLC_fsproj
-- autocmd! BufWritePost *.fsproj call fsharp#OnFSProjSave()
--augroup END
---- end ftplugin section ----



local function create_manager(config)
  validate {
    cmd = { config.cmd, "t", true },
    root_dir = { config.root_dir, "f", true },
    filetypes = { config.filetypes, "t", true },
    on_attach = { config.on_attach, "f", true },
    on_new_config = { config.on_new_config, "f", true },
  }

  local default_config = tbl_extend("keep", M.GetDefaultLspConfig(), util.default_config)
  config = tbl_extend("keep", config, default_config)

  local _
  if config.filetypes then
    _ = "FileType " .. table.concat(config.filetypes, ",")
  else
    _ = "BufReadPost *"
  end

  local get_root_dir = config.root_dir

  function M.Autostart()
    local root_dir = get_root_dir(api.nvim_buf_get_name(0), api.nvim_get_current_buf())
    if not root_dir then
      root_dir = util.path.dirname(api.nvim_buf_get_name(0))
    end
    if not root_dir then
      root_dir = vim.fn.getcwd()
    end
    root_dir = string.gsub(root_dir, "\\", "/")
    api.nvim_command(
      string.format(
        "autocmd %s lua require'ionide'.manager.try_add_wrapper()",
        "BufReadPost " .. root_dir .. "/*"
      )
    )
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local buf_dir = api.nvim_buf_get_name(bufnr)
      if buf_dir:sub(1, root_dir:len()) == root_dir then
        M.Manager.try_add_wrapper(bufnr)
      end
    end
  end

  local reload = false
  if M.Manager then
    for _, client in ipairs(M.Manager.clients()) do
      client.stop(true)
    end
    reload = true
    M.Manager = nil
  end

  function M.MakeConfig(_root_dir)
    local new_config = vim.tbl_deep_extend("keep", vim.empty_dict(), config)
    new_config = vim.tbl_deep_extend("keep", new_config, default_config)
    new_config.capabilities = new_config.capabilities or lsp.protocol.make_client_capabilities()
    new_config.capabilities = vim.tbl_deep_extend("keep", new_config.capabilities, {
      workspace = {
        configuration = true,
      },
    })
    if config.on_new_config then
      pcall(config.on_new_config, new_config, _root_dir)
    end
    new_config.on_init = util.add_hook_after(new_config.on_init, function(client, _)
      function client.workspace_did_change_configuration(settings)
        if not settings then
          return
        end
        if vim.tbl_isempty(settings) then
          settings = { [vim.type_idx] = vim.types.dictionary }
        end
        local settingsInspected = vim.inspect(settings)
        vim.notify("Settings being sent to LSP server are: " .. settingsInspected)
        return client.notify("workspace/didChangeConfiguration", {
          settings = settings,
        })
      end

      if not vim.tbl_isempty(new_config.settings) then
        local settingsInspected = vim.inspect(new_config.settings)
        vim.notify("Settings being sent to LSP server are: " .. settingsInspected)
        client.workspace_did_change_configuration(new_config.settings)
      end
    end)
    new_config._on_attach = new_config.on_attach
    new_config.on_attach = vim.schedule_wrap(function(client, bufnr)
      if bufnr == api.nvim_get_current_buf() then
        M._setup_buffer(client.id, bufnr)
      else
        api.nvim_command(
          string.format(
            "autocmd BufEnter <buffer=%d> ++once lua require'ionide'._setup_buffer(%d,%d)",
            bufnr,
            client.id,
            bufnr
          )
        )
      end
    end)
    new_config.root_dir = _root_dir
    return new_config
  end

  local manager = util.server_per_root_dir_manager(function(_root_dir) return M.MakeConfig(_root_dir) end)
  function manager.try_add(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if api.nvim_buf_get_option(bufnr, 'buftype') == 'nofile' then
      return
    end
    local root_dir = get_root_dir(api.nvim_buf_get_name(bufnr), bufnr)
    local id = manager.add(root_dir)
    if id then
      lsp.buf_attach_client(bufnr, id)
    end
  end

  function manager.try_add_wrapper(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local buftype = api.nvim_buf_get_option(bufnr, 'filetype')
    if buftype == 'fsharp' then
      manager.try_add(bufnr)
      return
    end
  end

  M.Manager = manager
  if reload and not (config.autostart == false) then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      manager.try_add_wrapper(bufnr)
    end
  else
    M.AutoStartIfNeeded(M, config)
  end
end

-- partially adopted from neovim/nvim-lspconfig, see lspconfig.LICENSE.md
function M._setup_buffer(client_id, bufnr)
  local client = lsp.get_client_by_id(client_id)
  if not client then
    return
  end
  if client.config._on_attach then
    client.config._on_attach(client, bufnr)
  end
end

function M.InitializeDefaultFsiKeymapSettings()
  if not M.NvimSettings.FsiKeymap then
    M.NvimSettings.FsiKeymap = "vscode"
  end
  if vim.fn.has('nvim') then
    if M.NvimSettings.FsiKeymap == "vscode" then
      M.NvimSettings.FsiKeymapSend = "<M-cr>"
      M.NvimSettings.FsiKeymapToggle = "<M-@>"
    elseif M.NvimSettings.FsiKeymap == "vim-fsharp" then
      M.NvimSettings.FsiKeymapSend   = "<leader>i"
      M.NvimSettings.FsiKeymapToggle = "<leader>e"
    elseif M.NvimSettings.FsiKeymap == "custom" then
      M.NvimSettings.FsiKeymap = "none"
      if not M.NvimSettings.FsiKeymapSend then
        vim.cmd.echoerr("FsiKeymapSend not set. good luck with that I dont have a nice way to change it yet. sorry. ")
      elseif not M.NvimSettings.FsiKeymapToggle then
        vim.cmd.echoerr("FsiKeymapToggle not set. good luck with that I dont have a nice way to change it yet. sorry. ")
      else
        M.NvimSettings.FsiKeymap = "custom"
      end
    end
  else
    vim.notify("I'm sorry I don't support regular vim, try ionide/ionide-vim instead")
  end
end

function M.setup(config)
  M.PassedInConfig = config
  M.NvimSettings = M.LoadNvimSettings()
  M.DefaultServerSettings = M.LoadDefaultServerSettings()
  M.DefaultLspConfig = M.GetDefaultLspConfig()
  M.InitializeDefaultFsiKeymapSettings()
  M.MergedConfig = vim.tbl_deep_extend("keep", config, M.DefaultLspConfig)
  if lspconfig_is_present then
    return M.DelegateToLspConfig(config)
  end
  return create_manager(config)
end

function M.status()
  if lspconfig_is_present then
    print("* LSP server: handled by nvim-lspconfig")
  elseif M.Manager ~= nil then
    if next(M.Manager.clients()) == nil then
      print("* LSP server: not started")
    else
      print("* LSP server: started")
    end
  else
    print("* LSP server: not initialized")
  end
end

--     " FSI keymaps
--     if g:fsharp#fsi_keymap == "vscode"
--         if has('nvim')
--             let g:fsharp#fsi_keymap_send   = "<M-cr>"
--             let g:fsharp#fsi_keymap_toggle = "<M-@>"
--         else
--             let g:fsharp#fsi_keymap_send   = "<esc><cr>"
--             let g:fsharp#fsi_keymap_toggle = "<esc>@"
--         endif
--     elseif g:fsharp#fsi_keymap == "vim-fsharp"
--         let g:fsharp#fsi_keymap_send   = "<leader>i"
--         let g:fsharp#fsi_keymap_toggle = "<leader>e"
--     elseif g:fsharp#fsi_keymap == "custom"
--         let g:fsharp#fsi_keymap = "none"
--         if !exists('g:fsharp#fsi_keymap_send')
--             echoerr "g:fsharp#fsi_keymap_send is not set"
--         elseif !exists('g:fsharp#fsi_keymap_toggle')
--             echoerr "g:fsharp#fsi_keymap_toggle is not set"
--         else
--             let g:fsharp#fsi_keymap = "custom"
--         endif
--     endif
--



-- " " FSI integration
--"
--" let s:fsi_buffer = -1
--" let s:fsi_job    = -1
--" let s:fsi_width  = 0
--" let s:fsi_height = 0
local fsiBuffer = -1
local fsiJob = -1
local fsiWidth = 0
local fsiHeight = 0
--"
--" function! s:win_gotoid_safe(winid)
--"     function! s:vimReturnFocus(window)
--"         call win_gotoid(a:window)
--"         redraw!
--"     endfunction
--"     if has('nvim')
--"         call win_gotoid(a:winid)
--"     else
--"         call timer_start(1, { -> s:vimReturnFocus(a:winid) })
--"     endif
--" endfunction
local function vimReturnFocus(window)
  vim.fn.win_gotoid(window)
  vim.cmd.redraw("!")
end

local function winGoToIdSafe(id)

  if vim.fn.has('nvim') then
    vim.fn.win_gotoid(id)
  else
    vim.fn.timer_start(1, function() vimReturnFocus(id) end, {})
  end
end

--"
--" function! s:get_fsi_command()
--"     let cmd = g:fsharp#fsi_command
--"     for prm in g:fsharp#fsi_extra_parameters
--"         let cmd = cmd . " " . prm
--"     endfor
--"     return cmd
--" endfunction

local function getFsiCommand()
  local cmd = M.FsiCommand or "dotnet fsi"
  local ep = M.FSIExtraParameters or {}
  for _, x in pairs(ep) do
    cmd = cmd .. ' ' .. x
  end
  return cmd

end

function M.OpenFsi(returnFocus)
  vim.notify("openfsi return focus is " .. tostring(returnFocus))
  local isNeovim = vim.fn.has('nvim')
  --"     if bufwinid(s:fsi_buffer) <= 0
  if vim.fn.bufwinid(fsiBuffer) <= 0 then
    vim.notify("fsiBuffer id is " .. tostring(fsiBuffer))
    --"         let fsi_command = s:get_fsi_command()
    local cmd = getFsiCommand()
    --"         if exists('*termopen') || exists('*term_start')
    if vim.fn.exists('*termopen') == true or vim.fn.exists('*term_start') then
      --"             let current_win = win_getid()
      local currentWin = vim.fn.win_getid()
      --"             execute g:fsharp#fsi_window_command
      vim.fn.execute(M.FsiWindowCommand or 'botright 10new')
      --"             if s:fsi_width  > 0 | execute 'vertical resize' s:fsi_width | endif
      if fsiWidth > 0 then vim.fn.execute('vertical resize ' .. fsiWidth) end
      --"             if s:fsi_height > 0 | execute 'resize' s:fsi_height | endif

      if fsiHeight > 0 then vim.fn.execute('resize ' .. fsiHeight) end
      --"             " if window is closed but FSI is still alive then reuse it
      --"             if s:fsi_buffer >= 0 && bufexists(str2nr(s:fsi_buffer))
      if fsiBuffer >= 0 and vim.fn.bufexists(fsiBuffer) then
        --"                 exec 'b' s:fsi_buffer
        vim.fn.cmd('b' .. tostring(fsiBuffer))
        --"                 normal G
        vim.cmd("normal G")
        --"                 if !has('nvim') && mode() == 'n' | execute "normal A" | endif
        if not isNeovim and vim.api.nvim_get_mode()[1] == 'n' then
          vim.cmd("normal A")
        end
        --"                 if a:returnFocus | call s:win_gotoid_safe(current_win) | endif
        if returnFocus then winGoToIdSafe(currentWin) end
        --"             " open FSI: Neovim
        --"             elseif has('nvim')
      elseif isNeovim then
        --"                 let s:fsi_job = termopen(fsi_command)
        fsiJob = vim.fn.termopen(cmd) or 0
        --"                 if s:fsi_job > 0
        if fsiJob > 0 then
          --"                     let s:fsi_buffer = bufnr("%")
          fsiBuffer = vim.fn.bufnr(vim.api.nvim_get_current_buf())
          --"                 else
        else
          --"                     close
          vim.cmd.close()
          --"                     echom "[FSAC] Failed to open FSI."
          vim.notify("[Ionide] failed to open FSI")
          --"                     return -1
          return -1
          --"                 endif
        end
        --"             " open FSI: Vim
        --"             else
      else
        --"                 let options = {
        local options = {
          term_name = "F# Interactive",
          curwin = 1,
          term_finish = "close"
        }
        --"                 \ "term_name": "F# Interactive",

        --"                 \ "curwin": 1,

        --"                 \ "term_finish": "close"

        --"                 \ }

        --"                 let s:fsi_buffer = term_start(fsi_command, options)
        fsiBuffer = vim.fn("term_start(" .. M.FsiCommand .. ", " .. vim.inspect(options) .. ")")
        --"                 if s:fsi_buffer != 0
        if fsiBuffer ~= 0 then
          --"                     if exists('*term_setkill') | call term_setkill(s:fsi_buffer, "term") | endif
          if vim.fn.exists('*term_setkill') == true then vim.fn("term_setkill(" .. fsiBuffer .. [["term"]]) end
          --"                     let s:fsi_job = term_getjob(s:fsi_buffer)
          fsiJob = vim.cmd.term_getjob(fsiBuffer)
          --"                 else
        else
          --"                     close

          vim.cmd.close()
          --"                     echom "[FSAC] Failed to open FSI."

          vim.notify("[Ionide] failed to open FSI")
          --"                     return -1
          return -1
          --"                 endif

        end
        --"             endif

      end
      --"             setlocal bufhidden=hide

      vim.opt_local.bufhidden = "hide"
      --"             normal G

      vim.cmd("normal G")
      --"             if a:returnFocus | call s:win_gotoid_safe(current_win) | endif
      if returnFocus then winGoToIdSafe(currentWin) end
      --"             return s:fsi_buffer
      return fsiBuffer
      --"         else
    else
      --"             echom "[FSAC] Your (neo)vim does not support terminal".
      vim.notify("[Ionide] Your neovim doesn't support terminal.")
      --"             return 0
      return 0
      --"         endif
    end
    --"     endif
  end
  return fsiBuffer
  --" endfunction
end

-- function M.OpenFsi(returnFocus)
--   vim.notify("OpenFsi got return focus as " .. vim.inspect(returnFocus))
--   local isNeovim = vim.fn.has('nvim')
--   if not isNeovim then
--     vim.notify("[Ionide] This version of ionide is for Neovim only. please try www.github.com/ionide/ionide-vim")
--   end
--     if vim.fn.exists('*termopen') == true or vim.fn.exists('*term_start') then
--       --"             let current_win = win_getid()
--       local currentWin = vim.fn.win_getid()
--     vim.notify("OpenFsi currentWin = " .. vim.inspect(currentWin))
--       --"             execute g:fsharp#fsi_window_command
--       vim.fn.execute(M.FsiWindowCommand or 'botright 10new')
--       -- "             if s:fsi_width  > 0 | execute 'vertical resize' s:fsi_width | endif
--       if fsiWidth > 0 then vim.fn.execute('vertical resize ' .. fsiWidth) end
--       --"             if s:fsi_height > 0 | execute 'resize' s:fsi_height | endif
--       if fsiHeight > 0 then vim.fn.execute('resize ' .. fsiHeight) end
--       --"             " if window is closed but FSI is still alive then reuse it
--       --"             if s:fsi_buffer >= 0 && bufexists(str2nr(s:fsi_buffer))
--       if fsiBuffer >= 0 and vim.fn.bufexists(fsiBuffer) then
--         --"                 exec 'b' s:fsi_buffer
--         vim.fn.cmd('b' .. tostring(fsiBuffer))
--         --"                 normal G
--
--         vim.cmd("normal G")
--         --"                 if a:returnFocus | call s:win_gotoid_safe(current_win) | endif
--         if returnFocus then winGoToIdSafe(currentWin) end
--         --"             " open FSI: Neovim
--         --"             elseif has('nvim')
--   local bufWinid = vim.fn.bufwinid(fsiBuffer) or -1
--   vim.notify("OpenFsi bufWinid = " .. vim.inspect(bufWinid))
--   if bufWinid <= 0 then
--     local cmd = getFsiCommand()
--     if isNeovim then
--       fsiJob = vim.fn.termopen(cmd)
--       vim.notify("OpenFsi fsiJob is now  = " .. vim.inspect(fsiJob))
--       if fsiJob > 0 then
--         fsiBuffer = vim.fn.bufnr(vim.api.nvim_get_current_buf())
--       else
--         vim.cmd.close()
--         vim.notify("[Ionide] failed to open FSI")
--         return -1
--       end
--     end
--   end
--   vim.notify("[Ionide] This version of ionide is for Neovim only. please try www.github.com/ionide/ionide-vim")
--   if returnFocus then winGoToIdSafe(currentWin) end
--   return fsiBuffer
-- end
--
--"
--" function! fsharp#toggleFsi()
--"     let fsiWindowId = bufwinid(s:fsi_buffer)
--"     if fsiWindowId > 0
--"         let current_win = win_getid()
--"         call win_gotoid(fsiWindowId)
--"         let s:fsi_width = winwidth('%')
--"         let s:fsi_height = winheight('%')
--"         close
--"         call win_gotoid(current_win)
--"     else
--"         call fsharp#openFsi(0)
--"     endif
--" endfunction

function M.ToggleFsi()
  local w = vim.fn.bufwinid(fsiBuffer)
  if w > 0 then
    local curWin = vim.fn.win_getid()
    M.winGoToId(w)
    fsiWidth = vim.fn.winwidth(tonumber(vim.fn.expand('%')) or 0)
    fsiHeight = vim.fn.winheight(tonumber(vim.fn.expand('%')) or 0)
    vim.cmd.close()
    vim.fn.win_gotoid(curWin)
  else
    M.OpenFsi()
  end
end

local function get_visual_selection()
  local s_start = vim.fn.getpos("'<")
  local s_end = vim.fn.getpos("'>")
  local n_lines = math.abs(s_end[2] - s_start[2]) + 1
  local lines = vim.api.nvim_buf_get_lines(0, s_start[2] - 1, s_end[2], false)
  lines[1] = string.sub(lines[1], s_start[3], -1)
  if n_lines == 1 then
    lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3] - s_start[3] + 1)
  else
    lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3])
  end
  return table.concat(lines, '\n')
end

function M.GetVisualSelection()
  -- vim.notify("getting visual selection")
  local line_start, column_start = unpack(vim.fn.getpos("'<"), 2)
  -- local column_start = vim.fn.getpos("'<")[3]
  -- vim.notify("line start: " .. line_start .. " column_start:" .. column_start)
  local line_end, column_end = unpack(vim.fn.getpos("'>"), 2)
  -- vim.notify("line end: " .. line_end .. " column_end:" .. column_end)
  local lines = vim.fn.getline(line_start, line_end)
  -- vim.notify("number of lines: " .. vim.inspect(#lines))
  local len = #lines
  if len == 0 then
    return {}
  end

  local inclusive = vim.o.selection == "inclusive"
  local columnSelectionSubraction = (function()

    if inclusive then
      return 1
    else
      return 2
    end
  end)()
  lines[len] = string.sub(lines[len], 0, column_end - columnSelectionSubraction)
  lines[1] = string.sub(lines[1], column_start)
  -- vim.notify("lines: \n" .. vim.inspect(lines))
  return lines
end

--"
--" function! fsharp#quitFsi()
--"     if s:fsi_buffer >= 0 && bufexists(str2nr(s:fsi_buffer))
--"         if has('nvim')
--"             let winid = bufwinid(s:fsi_buffer)
--"             if winid > 0 | execute "close " . winid | endif
--"             call jobstop(s:fsi_job)
--"         else
--"             call job_stop(s:fsi_job, "term")
--"         endif
--"         let s:fsi_buffer = -1
--"         let s:fsi_job = -1
--"     endif
--" endfunction
function M.QuitFsi()
  if vim.api.nvim_buf_is_valid(fsiBuffer) then
    local is_neovim = vim.api.nvim_eval("has('nvim')")
    if is_neovim then
      local winid = vim.api.nvim_call_function("bufwinid", { fsiBuffer })
      if winid > 0 then
        vim.api.nvim_win_close(winid, true)
      end
    end
    vim.api.nvim_call_function("jobstop", { fsiJob })
    fsiBuffer = -1
    fsiJob = -1
  end
end

--" function! fsharp#resetFsi()
--"     call fsharp#quitFsi()
--"     return fsharp#openFsi(1)
--" endfunction
--"
function M.ResetFsi()
  M.QuitFsi()
  M.OpenFsi(false)
end

--" function! fsharp#sendFsi(text)
--"     if fsharp#openFsi(!g:fsharp#fsi_focus_on_send) > 0
--"         " Neovim
--"         if has('nvim')
--"             call chansend(s:fsi_job, a:text . "\n" . ";;". "\n")
--"         " Vim 8
--"         else
--"             call term_sendkeys(s:fsi_buffer, a:text . "\<cr>" . ";;" . "\<cr>")
--"             call term_wait(s:fsi_buffer)
--"         endif
--"     endif
--" endfunction
-- "

function M.SendFsi(text)
  vim.notify("[Ionide] Text being sent to FSI:\n" .. text)
  local openResult = M.OpenFsi(not M.FsiFocusOnSend or false)
  vim.notify("[Ionide] result of openfsi function is " .. vim.inspect(openResult))
  if not openResult then
    openResult = 1
    vim.notify("[Ionide] changing result to 1 and hoping for the best. lol. " .. vim.inspect(openResult))
  end

  if openResult > 0 then
    if vim.fn.has('nvim') then
      vim.fn.chansend(fsiJob, text .. "\n" .. ";;" .. "\n")
    else
      vim.api.nvim_call_function("term_sendkeys", { fsiBuffer, text .. "\\<cr>" .. ";;" .. "\\<cr>" })
      vim.api.nvim_call_function("term_wait", { fsiBuffer })
    end
  end
end

function M.GetCompleteBuffer()
  return vim.fn.join(vim.fn.getline(1, tonumber(vim.fn.expand('$'))), "\n")
end

function M.SendSelectionToFsi()

  -- vim.cmd(':normal' .. vim.fn.len(lines) .. 'j')
  local lines = M.GetVisualSelection()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), 'x', true)
  vim.cmd(':normal' .. ' j')
  -- vim.cmd('normal' .. vim.fn.len(lines) .. 'j')
  local text = vim.fn.join(lines, "\n")
  -- vim.notify("fsi send selection " .. text)
  M.SendFsi(text)

  local line_end, _ = unpack(vim.fn.getpos("'>"), 2)


  vim.api.nvim_win_set_cursor(0, { line_end + 1, 0 })

  -- vim.cmd(':normal' .. vim.fn.len(lines) .. 'j')
end

function M.SendLineToFsi()
  local text = vim.api.nvim_get_current_line()
  -- vim.notify("fsi send line " .. text)
  M.SendFsi(text)
  vim.cmd 'normal j'
end

function M.SendAllToFsi()
  -- vim.notify("fsi send all ")
  local text = M.GetCompleteBuffer()
  return M.SendFsi(text)
end

-- if g:fsharp#fsi_keymap != "none"
--     execute "vnoremap <silent>" g:fsharp#fsi_keymap_send ":call fsharp#sendSelectionToFsi()<cr><esc>"
--     execute "nnoremap <silent>" g:fsharp#fsi_keymap_send ":call fsharp#sendLineToFsi()<cr>"
--     execute "nnoremap <silent>" g:fsharp#fsi_keymap_toggle ":call fsharp#toggleFsi()<cr>"
--     execute "tnoremap <silent>" g:fsharp#fsi_keymap_toggle "<C-\\><C-n>:call fsharp#toggleFsi()<cr>"
-- endif
function M.SetKeymaps()

  -- vim.notify("[Ionide] Setting keymaps..")
  -- vim.notify("keymap send is: " .. (M.FsiKeymapSend or "somehow nil? setting to vscode style default"))
  -- vim.notify("keymap toggle is: " .. (M.FsiKeymapToggle or "somehow nil? setting to vscode style default "))
  local send = M.FsiKeymapSend or "<M-CR>"
  local toggle = M.FsiKeymapToggle or "<M-@>"
  vim.keymap.set("v", send, function() M.SendSelectionToFsi() end, { silent = false })
  vim.keymap.set("n", send, function()
    -- vim.notify("[Ionide] jsut pressed " .. send .. " in normal mode. expecting to send line to fsi. ")
    M.SendLineToFsi()
  end, { silent = false })
  vim.keymap.set("n", toggle, function() M.ToggleFsi() end, { silent = false })
  vim.keymap.set("t", toggle, function() M.ToggleFsi() end, { silent = false })

end

return M

