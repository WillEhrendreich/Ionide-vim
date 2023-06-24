--  www.github.com/willehrendreich/ionide-vim
local vim = vim
local validate = vim.validate
local api = vim.api
local uc = vim.api.nvim_create_user_command
local lsp = vim.lsp
-- local log = require('vim.lsp.log')
-- local protocol = require('vim.lsp.protocol')
local tbl_extend = vim.tbl_extend
local autocmd = vim.api.nvim_create_autocmd
local grp = vim.api.nvim_create_augroup
local plenary = require("plenary")
local F = plenary.functional



---@class PackageReference
---@field FullPath string
---@field Name string
---@field Version string

---@class ProjectReference
---@field ProjectFileName string
---@field RelativePath string

---@class ProjectInfo.Item
-- The full FilePath
---@field FilePath string
---Metadata
---@field Metadata table
---Name = "Compile",
---@field Name string
---VirtualPath = "DebuggingTp/Shared.fs"
---@field VirtualPath string


---@class ProjectInfo.Info.RunCmd
---@field Arguments string
---@field Command string

---@class ProjectInfo.Info
  --   Configuration = "Debug","Release"
---@field Configuration string
    --   IsPackable = true,
---@field IsPackable boolean
    --   IsPublishable = true,
---@field IsPublishable boolean
    --   IsTestProject = false,
---@field IsTestProject boolean
    --   RestoreSuccess = true,
---@field RestoreSuccess boolean
    --   RunCmd = vim.NIL,
---@field RunCmd ProjectInfo.Info.RunCmd|nil
    --   TargetFramework = "netstandard2.0",
---@field TargetFramework string
    --   TargetFrameworkIdentifier = ".NETStandard",
---@field TargetFrameworkIdentifier string
    --   TargetFrameworkVersion = "v2.0",
---@field TargetFrameworkVersion string
    --   TargetFrameworks = { "netstandard2.0" }
---@field TargetFrameworks  string[]


---@class ProjectInfo
---@field AdditionalInfo table
---@field Files string[]
---@field Info ProjectInfo.Info
---@field Items ProjectInfo.Item[]
    -- full Output file path, usually with things like bin/debug/{TargetFramework}/{AssemblyName}.dll
---@field Output string
    -- OutputType = "lib", "exe"
---@field OutputType string
    -- PackageReferences = all the nuget package references
---@field PackageReferences PackageReference[]
    -- Project path, absolute, not  relative.
---@field Project string
    -- ProjectReferences - all the other projects this project references.
---@field ProjectReferences ProjectReference[]
    -- References - all the dll's this project references.
---@field References string[]


---@class ProjectDataTable
---@field Configurations table

---@class ProjectKind
---@field Data ProjectDataTable
---@field Kind string

---@class Project
---@field Guid string
---@field Kind ProjectKind -- likely should always be "msbuildformat"
---@field Name string -- the FilePath

---@class SolutionData
---@field Configurations table
---@field Items Project[]
---@field Path string

---@class Solution
---@field Data SolutionData
---@field Type string --should only ever be "solution"


-- used for "fsharp/documentationSymbol" - accepts DocumentationForSymbolReuqest,
-- returns documentation data about given symbol from given assembly, used for InfoPanel
-- original fsharp type declaration :
-- type DocumentationForSymbolReuqest = { XmlSig: string; Assembly: string }
---@class FSharpDocumentationForSymbolRequest
---@field XmlSig string
---@field Assembly string


--- for calling "fsharp/workspaceLoad" -
--- accepts WorkspaceLoadParms, loads given list of projects in the background,
--- partial result notified by fsharp/notifyWorkspace notification
--- original FSharp Type Definition:
--- type WorkspaceLoadParms =
---   {
---     /// Project files to load
---     TextDocuments: TextDocumentIdentifier[]
---   }
---@class FSharpWorkspaceLoadParams
---@field TextDocuments lsp.TextDocumentIdentifier[]




--- for calling "fsharp/workspacePeek" - accepts WorkspacePeekRequest,
--- returns list of possible workspaces (resolved solution files,
--- or list of projects if there are no solution files)
--- original FSharp Type Definition:
--- type WorkspacePeekRequest =
---   { Directory: string
---     Deep: int
---     ExcludedDirs: string array }
---@class FSharpWorkspacePeekRequest
---@field Directory string
---@field Deep integer
---@field ExcludedDirs string[]

-- type PlainNotification = { Content: string }
--
-- /// Notification when a `TextDocument` is completely analyzed:
-- /// F# Compiler checked file & all Analyzers (like `UnusedOpensAnalyzer`) are done.
-- ///
-- /// Used to signal all Diagnostics for this `TextDocument` are collected and sent.
-- /// -> For tests to get all Diagnostics of `TextDocument`
-- type DocumentAnalyzedNotification =
--   { TextDocument: VersionedTextDocumentIdentifier }
--
-- type TestDetectedNotification =
--   { File: string
--     Tests: TestAdapter.TestAdapterEntry<Range> array }
--
-- type ProjectParms =
--   {
--     /// Project file to compile
--     Project: TextDocumentIdentifier
--   }
---@class FSharpProjectParams
---@field Project lsp.TextDocumentIdentifier


-- type HighlightingRequest =
--   { TextDocument: TextDocumentIdentifier }
--
-- type LineLensConfig = { Enabled: string; Prefix: string }
--
-- type FsdnRequest = { Query: string }
--
-- type DotnetNewListRequest = { Query: string }
--
-- type DotnetNewRunRequest =
--   { Template: string
--     Output: string option
--     Name: string option }
--
-- type DotnetProjectRequest = { Target: string; Reference: string }
--
-- type DotnetFileRequest =
--   { FsProj: string
--     FileVirtualPath: string }
--
-- type DotnetFile2Request =
--   { FsProj: string
--     FileVirtualPath: string
--     NewFile: string }
--
-- type DotnetRenameFileRequest =
--   { FsProj: string
--     OldFileVirtualPath: string
--     NewFileName: string }
--
-- type FSharpLiterateRequest =
--   { TextDocument: TextDocumentIdentifier }
--
-- type FSharpPipelineHintRequest =
--   { TextDocument: TextDocumentIdentifier }
--


---determines if input string ends with the suffix given.
---@param s string
---@param suffix string
---@return boolean
local function stringEndsWith(s, suffix)
  return s:sub(- #suffix) == suffix
end


local function try_require(...)
  local status, lib = pcall(require, ...)
  if status then
    return lib
  end
  return nil
end

local M = {}
M.workspace_folders = {}

---@type table<string,ProjectInfo>
M.Projects = {}

---@table<string,function>
M.Handlers = {[""]=function(err,rs,ctx,config) vim.notify("if you're seeing this called, something went wrong, it's key is literally an empty string.  ") end}

---@type lspconfig.options.fsautocomplete
M.MergedConfig = {}

---@type _.lspconfig.settings.fsautocomplete.FSharp
M.DefaultServerSettings = {
  --   { AutomaticWorkspaceInit: bool option AutomaticWorkspaceInit = false
  -- automaticWorkspaceInit = true,
  --     WorkspaceModePeekDeepLevel: int option WorkspaceModePeekDeepLevel = 2
  workspaceModePeekDeepLevel = 4,

  fsac = {
    attachDebugger = false,
    -- cachedTypeCheckCount = 200,
    conserveMemory = true,
    silencedLogs = {},
    -- parallelReferenceResolution = true,
    dotnetArgs = {},
    -- netCoreDllPath = "",
  },

  enableAdaptiveLspServer = true,
  --     ExcludeProjectDirectories: string[] option = [||]
  excludeProjectDirectories = { "paket-files", ".fable", "packages", "node_modules" },
  --     KeywordsAutocomplete: bool option false
  keywordsAutocomplete = true,
  --     ExternalAutocomplete: bool option false
  externalAutocomplete = false,
  --     Linter: bool option false
  linter = true,
  --     IndentationSize: int option 4
  indentationSize = 2,
  --     UnionCaseStubGeneration: bool option false
  unionCaseStubGeneration = true,
  --     UnionCaseStubGenerationBody: string option """failwith "Not Implemented" """
  unionCaseStubGenerationBody = 'failwith "Not Implemented"',
  --     RecordStubGeneration: bool option false
  recordStubGeneration = true,
  --     RecordStubGenerationBody: string option "failwith \"Not Implemented\""
  recordStubGenerationBody = 'failwith "Not Implemented"',
  --     InterfaceStubGeneration: bool option false
  interfaceStubGeneration = true,
  --     InterfaceStubGenerationObjectIdentifier: string option "this"
  interfaceStubGenerationObjectIdentifier = "this",
  --     InterfaceStubGenerationMethodBody: string option "failwith \"Not Implemented\""
  interfaceStubGenerationMethodBody = 'failwith "Not Implemented"',
  --     UnusedOpensAnalyzer: bool option false
  unusedOpensAnalyzer = true,
  --     UnusedDeclarationsAnalyzer: bool option false
  unusedDeclarationsAnalyzer = true,
  --     SimplifyNameAnalyzer: bool option false
  simplifyNameAnalyzer = true,
  --     ResolveNamespaces: bool option false
  resolveNamespaces = true,
  --     EnableAnalyzers: bool option false
  enableAnalyzers = true,
  --     AnalyzersPath: string[] option
  analyzersPath = { "packages/Analyzers", "analyzers" },
  --     DisableInMemoryProjectReferences: bool option false|
  -- disableInMemoryProjectReferences = false,

  --     LineLens: LineLensConfig option
  -- lineLens = { enabled = "always", prefix = "ll//" },
  --     UseSdkScripts: bool option false
  -- useSdkScripts = true,
  -- = true,
  suggestSdkScripts = true,
  --     DotNetRoot: string option  Environment.dotnetSDKRoot.Value.FullName
  dotnetRoot = "",
  -- (function()
  --   local function find_executable(name)
  --     local path = os.getenv("PATH") or ""
  --     for dir in string.gmatch(path, "[^:]+") do
  --       local executable = dir .. "/" .. name .. ".exe"
  --       if os.execute("test -x " .. executable) == 1 then
  --         return dir .. "/"
  --       end
  --     end
  --     return nil
  --   end
  --
  --   local dnr = os.getenv("DOTNET_ROOT")
  --   if dnr and not dnr == "" then
  --     return dnr
  --   else
  --     if vim.fn.has("win32") then
  --       local canExecute = vim.fn.executable("dotnet") == 1
  --       if not canExecute then
  --         local vs1 = vim.fs.find({ "fscAnyCpu.exe" },
  --                 { path = "C:/Program Files/Microsoft Visual Studio", type = "file" })
  --         local vs2 = vim.fs.find({ "fscAnyCpu.exe" },
  --                 { path = "C:/Program Files (x86)/Microsoft Visual Studio", type = "file" })
  --         return vs1 or vs2 or ""
  --       else
  --         local dn = vim.fs.find({ "dotnet.exe" }, { path = "C:/Program Files/dotnet/", type = "file" })
  --         return dn or find_executable("dotnet") or ""
  --       end
  --     else
  --       return ""
  --     end
  --     return ""
  --   end
  -- end)()[1]

  --     FSIExtraParameters: string[] option
  fsiExtraParameters = {},
  --     FSICompilerToolLocations: string[] option

  -- fsiCompilerToolLocations = {},
  --     TooltipMode: string option TooltipMode = "full"

  -- tooltipMode =  "",

  -- tooltipMode = "full",
  --     GenerateBinlog: bool option GenerateBinlog = false
  generateBinlog = false,
  --     AbstractClassStubGeneration: bool option AbstractClassStubGeneration = true
  abstractClassStubGeneration = true,
  --     AbstractClassStubGenerationObjectIdentifier: string option AbstractClassStubGenerationObjectIdentifier = "this"
  abstractClassStubGenerationObjectIdentifier = "this",
  --     AbstractClassStubGenerationMethodBody: string option, default = "failwith \"Not Implemented\""
  -- AbstractClassStubGenerationMethodBody = "failwith \"Not Implemented\""
  abstractClassStubGenerationMethodBody = 'failwith "Not Implemented"',
  --     CodeLenses: CodeLensConfigDto option
  --  type CodeLensConfigDto =
  -- { Signature: {| Enabled: bool option |} option
  --   References: {| Enabled: bool option |} option }

  ---@type _.lspconfig.settings.fsautocomplete.CodeLenses
  codeLenses = {
    signature = { enabled = true },
    references = { enabled = true },
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

  inlayHints = {
    disableLongTooltip = false,
    enabled = true,
    parameterNames = true,
    typeAnnotations = true,
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
  debug = {
    dontCheckRelatedFiles = false,
    checkFileDebouncerTimeout = 250,
    logDurationBetweenCheckFiles = false,
    logCheckFileDuration = false,
  },
}

M.NvimSettings = {
  FsautocompleteCommand = { "fsautocomplete" },
  UseRecommendedServerConfig = false,
  AutomaticWorkspaceInit = true,
  AutomaticReloadWorkspace = true,
  ShowSignatureOnCursorMove = true,
  FsiCommand = "dotnet fsi",
  --
  -- (function()
  --   local function determineFsiPath(useNetCore, ifNetFXUseAnyCpu)
  --     local pf, exe, arg, fsiExe
  --     if useNetCore == true then
  --       pf = os.getenv("ProgramW6432")
  --       if pf == nil or pf == "" then
  --         pf = os.getenv("ProgramFiles")
  --       end
  --       exe = pf .. "/dotnet/dotnet.exe"
  --       arg = "fsi"
  --       if not os.rename(exe, exe) then
  --         vim.notify("Could Not Find fsi.exe: " .. exe)
  --       end
  --       return exe .. " " .. arg
  --     else
  --       local function fsiExeName()
  --         local any = ifNetFXUseAnyCpu or true
  --         if any then
  --           return "fsiAnyCpu.exe"
  --           -- elseif runtime.architecture == "Arm64" then
  --           --   return "fsiArm64.exe"
  --         else
  --           return "fsi.exe"
  --         end
  --       end
  --
  --       -- - path (string): Path to begin searching from. If
  --       --        omitted, the |current-directory| is used.
  --       -- - upward (boolean, default false): If true, search
  --       --          upward through parent directories. Otherwise,
  --       --          search through child directories
  --       --          (recursively).
  --       -- - stop (string): Stop searching when this directory is
  --       --        reached. The directory itself is not searched.
  --       -- - type (string): Find only files ("file") or
  --       --        directories ("directory"). If omitted, both
  --       --        files and directories that match {names} are
  --       --        included.
  --       -- - limit (number, default 1): Stop the search after
  --       --         finding this many matches. Use `math.huge` to
  --       --         place no limit on the number of matches.
  --
  --       local function determineFsiRelativePath(name)
  --         local find = vim.fs.find({ name },
  --                 { path = vim.fn.getcwd(), upward = false, type = "file", limit = 1 })
  --         if vim.tbl_isempty(find) or find[1] == nil then
  --           return ""
  --         else
  --           return find[1]
  --         end
  --       end
  --
  --       local name = fsiExeName()
  --       local path = determineFsiRelativePath(name)
  --       if not path == "" then
  --         fsiExe = path
  --       else
  --         local fsbin = os.getenv("FSharpBinFolder")
  --         if fsbin == nil or fsbin == "" then
  --           local lastDitchEffortPath =
  --               vim.fs.find({ name },
  --                   {
  --                       path = "C:/Program Files (x86)/Microsoft Visual Studio/",
  --                       upward = false,
  --                       type = "file",
  --                       limit = 1
  --                   })
  --           if not lastDitchEffortPath then
  --             fsiExe = "Could not find FSI"
  --           else
  --             fsiExe = lastDitchEffortPath
  --           end
  --         else
  --           fsiExe = fsbin .. "/Tools/" .. name
  --         end
  --       end
  --       return fsiExe
  --     end
  --   end
  --
  --   local function shouldUseAnyCpu()
  --     local uname = vim.api.nvim_call_function("system", { "uname -m" })
  --     local architecture = uname:gsub("\n", "")
  --     if architecture == "" then
  --       local output = vim.api.nvim_call_function("system", { "cmd /c echo %PROCESSOR_ARCHITECTURE%" })
  --       architecture = output:gsub("\n", "")
  --     end
  --     if string.match(architecture, "64") then
  --       return true
  --     else
  --       return false
  --     end
  --   end
  --
  --   local useSdkScripts = false
  --   if M.DefaultServerSettings then
  --     local ds = M.DefaultServerSettings
  --     if ds.useSdkScripts then
  --       useSdkScripts = ds.useSdkScripts
  --     end
  --   end
  --   if not M.PassedInConfig then
  --     M["PassedInConfig"] = {}
  --   end
  --   if M.PassedInConfig.settings then
  --     if M.PassedInConfig.settings.FSharp then
  --       if M.PassedInConfig.settings.FSharp.useSdkScripts then
  --         useSdkScripts = M.PassedInConfig.settings.FSharp.useSdkScripts
  --       end
  --     end
  --   end
  --
  --   local useAnyCpu = shouldUseAnyCpu()
  --   return determineFsiPath(useSdkScripts, useAnyCpu)
  -- end)(),

  FsiKeymap = "vscode",
  FsiWindowCommand = "botright 10new",
  FsiFocusOnSend = false,
  LspAutoSetup = false,
  LspRecommendedColorscheme = true,
  LspCodelens = true,
  FsiVscodeKeymaps = true,
  Statusline = "Ionide",
  AutocmdEvents = {
    "LspAttach",
    "BufEnter",
    "BufWritePost",
    "CursorHold",
    "CursorHoldI",
    "InsertEnter",
    "InsertLeave",
  },
  FsiKeymapSend = "<M-cr>",
  FsiKeymapToggle = "<M-@>",
}

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
  vim.notify("handling notifyWorkspace")
  local content = vim.json.decode(payload.content)
  -- vim.notify("notifyWorkspace Decoded content is : \n"..vim.inspect(content))
  if content then
    if content.Kind == "projectLoading" then
      vim.notify("[Ionide] Loading " .. content.Data.Project)
      -- print("[Ionide] now calling AddOrUpdateThenSort on table  " .. vim.inspect(Workspace))
      --
      -- table.insert( M.Projects, content.Data.Project)
      -- -- local dir = vim.fs.dirname(content.Data.Project)
      -- M.workspace_folders = M.AddThenSort(dir, M.workspace_folders)
      -- print("after attempting to reassign table value it looks like this : " .. vim.inspect(Workspace))
    elseif content.Kind == "project" then
      local k= content.Data.Project
      local projInfo ={}
       projInfo[k] = content.Data
      -- local projects = { projInfo}
      M.Projects = vim.tbl_deep_extend("force",M.Projects ,projInfo)

    elseif content.Kind == "workspaceLoad" and content.Data.Status == "finished" then
      -- print("[Ionide] calling updateServerConfig ... ")
      -- print("[Ionide] before calling updateServerconfig, workspace looks like:   " .. vim.inspect(Workspace))
      for proj, projInfoData in pairs(M.Projects) do

        local dir = vim.fs.dirname(proj)
          if vim.tbl_contains(M.workspace_folders,dir) then
          else
          table.insert(M.workspace_folders,dir)
          end
        end
      M.UpdateServerConfig(M.MergedConfig.settings.FSharp)
      -- print("[Ionide] after calling updateServerconfig, workspace looks like:   " .. vim.inspect(Workspace))
      local projectCount = vim.tbl_count(M.Projects)
      if projectCount > 0 then
        if projectCount > 1 then
          vim.notify("[Ionide] Loaded " .. projectCount .. " projects:\n" .. vim.inspect(M.Projects))
        else
          vim.notify("[Ionide] Loaded project:\n" .. vim.inspect(M.Projects[1].Data.Name))
        end
      else
        vim.notify("[Ionide] Workspace is empty! Something went wrong. ")
      end
    end
  end
end






function M.HandleWorkspacePeek(result)
  -- vim.notify("handling workspacePeek response\n")
 -- vim.notify(
 --      "handling workspacePeek response\n"
 --      .. "result is: \n"
 --      .. vim.inspect(result or "Nothing came back from the server..")
 --    )

        -- vim.notify("result is: " .. vim.inspect(
        --   {
        --
        --     result = vim.inspect(result or "NO result"),
        --     -- err = vim.inspect(responseError or "NO err"),
        --     -- client_id = vim.inspect(handlerContext.client_id or "NO ctx clientid  "),
        --     -- method = vim.inspect(handlerContext.method),
        --     -- params = vim.inspect(handlerContext.params),
        --     -- bufnr = vim.inspect(handlerContext.bufnr or "NO ctx clientid  "),
        --   }))
  -- if result ~= nil then
    -- vim.notify(
    --   "handling workspacePeek response\n"
    --   .. "result is: \n"
    --   .. vim.inspect(result.content or "Nothing came back from the server..")
    -- )
    -- local content = vim.json.decode(result).content
    local resultContent = result.content
    -- vim.notify(
    --   -- "handling workspacePeek response\n"
    --   -- .. "result is: \n"
    --    vim.inspect(resultContent or "result.content could not be read correctly")
    -- )

    if resultContent ~= nil then
      local content =vim.json.decode(resultContent)
      -- vim.notify("json decode of payload content : ".. vim.inspect(content or "not decoded"))
    if content then
      -- vim.notify("json decode of payload content successful")
    local kind = content.Kind
      if kind and kind == "workspacePeek" then
        -- vim.notify("workspace peek is content kind")
        local data = content.Data
        if data ~= nil then
          -- vim.notify("Data not null")
          local found = data.Found
          if found ~= nil then
            -- vim.notify("data.Found not null")
            ---@type Solution []
            local solutions = {}
            local directory
            for _, item in ipairs(found) do
              if item.Type == "solution" then
                table.insert(solutions, item)
              elseif item.Type == "directory" then
                directory = vim.fs.normalize(item.Data.Directory)
              else

              end
            end
            local cwd =vim.fs.normalize( vim.fn.getcwd())
            if directory == cwd then
              -- vim.notify("WorkspacePeek directory \n"
              --   ..
              --   directory
              --   ..
              --   "\nEquals current working directory\n"
              --   .. cwd
              -- )
            else
              vim.notify("WorkspacePeek directory \n"
                ..
                directory
                ..
                "Does not equal current working directory\n"
                .. cwd
              )
            end

            -- local solutionToLoad
            if #solutions > 0 then
              -- vim.notify(vim.inspect(#solutions) .. " solutions found in workspace")
              if #solutions > 1 then
                -- vim.notify("More than one solution found in workspace!")
                vim.ui.select(solutions, {
                  prompt = "More than one solution found in workspace. Please pick one to load:",

                  format_item = function(item)
                    return vim.fn.fnamemodify(vim.fs.normalize(item.Data.Path),":p:.")
                  end

                }, function(choice, index)


                   local finalChoice =  solutions[index]
              local finalPath = vim.fs.normalize(finalChoice.Data.Path)
                   vim.notify("Chose to load solution : ".. vim.fn.fnamemodify(vim.fs.normalize(finalPath),":p:."))

                  ---@type string[]
                  local pathsToLoad = {}
                  local projects = finalChoice.Data.Items
                    for _,project in ipairs(projects) do
                      table.insert(pathsToLoad,vim.fs.normalize(project.Name))

                    end

              vim.notify("Going to ask FsAutoComplete to load these project paths.. \n"..  vim.inspect(table.concat(pathsToLoad,"\n")))
                   -- local  projectParams = F.map(M.CreateFSharpProjectParams, pathsToLoad)
                   local  projectParams ={}
                    for _, path in ipairs(pathsToLoad) do
                      table.insert(projectParams,M.CreateFSharpProjectParams(path))
                    end
                    for _, proj in ipairs(projectParams) do
                      vim.lsp.buf_request(0,"fsharp/project",{proj},
                        function (payload)
                          vim.notify("fsharp/project load request has a payload of :  " .. vim.inspect( payload or "No Result from Server")) end)

                    end

                -- M.CallLspNotify("workspace/didChangeConfiguration", M.MergedConfig.settings.FSharp)



                  -- return vim.fs.normalize(choice.Data.Path)
                end)
              else
               -- solutionToLoad = "THis should nefver happen"

              end
            end
            -- if solutionToLoad ~= nil then
            --   vim.notify("solutionToLoad is set to " ..
            --     solutionToLoad .. " \nthough currently that doesn't do anything..")
            -- else
            --   vim.notify("for some reason solution to load was null. .... why?")
            -- end
          else
            -- vim.notify("for some reason data.Found was null. .... why?")
          end
        else
          -- vim.notify("for some reason content.Data was null. .... why?")
        end
      else
        -- vim.notify("content.Type wasn't workspace peek.. that should be impossible.. .... why?")
      end
    else
      -- vim.notify("no content from Json decode? but it isn't null.... why?")
    end
  else
      -- vim.notify("no content from Json decode? but it isn't null.... why?")
  end
  -- else
  --   vim.notify("no result from workspace peek! WHY??!")
  -- end
end

function M.HandleCompilerLocation(error, result , context , config)
  vim.notify(
    "handling compilerLocation response\n"
    .. "result is: \n"
    .. vim.inspect(result or "Nothing came back from the server..")
  )
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

M["workspace/workspaceFolders"] = function(_, _, ctx)
  local client_id = ctx.client_id
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    -- vim.err_message("LSP[id=", client_id, "] client has shut down after sending the message")
    return
  end
  return client.workspace_folders or vim.NIL
end

local function GetHandlers()
return {
    ["fsharp/notifyWorkspace"]         = "HandleNotifyWorkspace",
    ["fsharp/workspacePeek"]           = "HandleWorkspacePeek",
    ["textDocument/documentHighlight"] = "HandleDocumentHighlight",
    ["fsharp/compilerLocation"]        = "HandleCompilerLocation",
}

end

function M.CreateHandlers()
  local h = GetHandlers()
  local r = {}
  for method, func_name in pairs(h) do
      -- vim.notify(
      --   "going to be handling " .. method .. " with ionide function named " .. func_name
      --     -- .. " request, here are the params \n"
      --   -- .. vim.inspect({ err or "", params or "", ctx or "", config or "" })
      -- )
    local handler = function(err, params, ctx, config)
      -- local handler = function(_, params, _, _)
      -- vim.notify(
      --   "going to be handling " .. method .. "/" .. func_name
          -- .. " request, here are the params \n"
        -- .. vim.inspect({ err or "", params or "", ctx or "", config or "" })
      -- )

      if func_name == "HandleCompilerLocation" then
        M[func_name](err or "No Error", params or "No Params", ctx or "No Context", config or "No Configs")
      -- end
      -- if method == "HandleWorkspacePeek" then
      -- vim.notify(
      --   "going to be handling " .. method
      --     -- .. " request, here are the params \n"
      --   -- .. vim.inspect({ err or "", params or "", ctx or "", config or "" })
      -- )
      -- M[method](params)
      -- end

      -- if method == "fsharp/workspacePeek" then
      -- vim.notify(
      --   -- "going to be handling " ..  method
      --   "handling " .. method .. " with ionide function named " .. func_name
      --     -- .. " request, here are the params \n"
      --   -- .. vim.inspect({ err or "", params or "", ctx or "", config or "" })
      -- )
      -- M[func_name](params)
      -- end
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

      -- if params == nil then
      --   M[func_name]()
      -- end
else
      M[func_name](params)
      -- end
  end
    end

    r[method] = handler
  end
    -- vim.notify("handlers should look like this in the end:\n "..vim.inspect(r))
  -- for k,hand in pairs(r) do
  --   vim.notify("now inserting "..vim.inspect(k).." , "..vim.inspect(hand).." into Handlers table")
  --   -- table.tbl_deep_extend(M.Handlers , hand)
  -- end
    M.Handlers = vim.tbl_deep_extend("force", M.Handlers ,r)
    -- vim.notify("HandlersTable looks like this:\n "..vim.inspect(M.Handlers))
  return r
end

---@type lspconfig.options.fsautocomplete
M.DefaultLspConfig = {
  -- local nvimSettings = M.NvimSettings or {}
  -- local serverSettings = M.DefaultServerSettings
  name = "ionide",
  cmd = M.NvimSettings.FsautocompleteCommand,
  -- cmd ={ 'fsautocomplete', '--adaptive-lsp-server-enabled', '-v' },
  -- cmd_env = { DOTNET_ROLL_FORWARD = "LatestMajor" },
  cmd_env = M.NvimSettings.cmdEnv or { DOTNET_ROLL_FORWARD = "LatestMajor" },
  filetypes = { "fsharp", "fsharp_project" },
  autostart = true,
  handlers = M.CreateHandlers(),
  init_options = { AutomaticWorkspaceInit = M.NvimSettings.AutomaticWorkspaceInit },
  on_init = M.Initialize,
  settings = { FSharp = M.DefaultServerSettings },
  -- root_dir = local_root_dir,M.GitFirstRootDir(n)
  root_dir = M.GitFirstRootDir,
  -- root_dir = util.root_pattern("*.sln"),
  log_level = lsp.protocol.MessageType.Warning,
  message_level = lsp.protocol.MessageType.Warning,
  capabilities = lsp.protocol.make_client_capabilities(),
}

---@type lspconfig.options.fsautocomplete
M.PassedInConfig = { settings = { FSharp = {} } }

-- M.MergedConfig = vim.deepcopy(M.DefaultLspConfig)
-- M.PassedInConfig = vim.deepcopy(M.DefaultLspConfig)

M.Manager = nil

local lspconfig_is_present = true
local util = try_require("lspconfig.util")
if util == nil then
  lspconfig_is_present = false
  util = require("ionide.util")
end

--- generates a key to look up the function call and assigns it to callbacks[newRandomIntKeyHere]
--- then returns the key it created
---@param methodname string
---@returns key integer
function M.RegisterCallback(methodname)
  local rnd = os.time()
  callbacks[rnd] = methodname
  M.CallBackResults[rnd] = methodname
  return rnd
end

--  function! s:PlainNotification(content)
--    return { 'Content': a:content }
-- endfunction

---@returns vim.lsp.PlainNotification
function M.PlainNotification(content)
  -- return vim.cmd("return 'Content': a:" .. content .. " }")
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

---creates a textDocumentIdentifier from a string path
---@param path string
---@return lsp.TextDocumentIdentifier
function M.TextDocumentIdentifier(path)
  local usr_ss_opt = vim.o.shellslash
  vim.o.shellslash = true
  local uri = vim.fn.fnamemodify(path, ":p")
  if string.sub(uri, 1, 1) == "/" then
    uri = "file://" .. uri
  else
    uri = "file:///" .. uri
  end
  vim.o.shellslash = usr_ss_opt

  ---@type lsp.TextDocumentIdentifier
  return { Uri = (uri) }
end

-- function! s:Position(line, character)
--     return { 'Line': a:line, 'Character': a:character }
-- endfunction

---Creates an lsp.Position from a line and character number
---@param line integer
---@param character integer
---@return lsp.Position
function M.Position(line, character)
  return { Line = line, Character = character }
end

-- function! s:TextDocumentPositionParams(documentUri, line, character)
--     return {
--         \ 'TextDocument': s:TextDocumentIdentifier(a:documentUri),
--         \ 'Position':     s:Position(a:line, a:character)
--         \ }
-- endfunction

---Creates a TextDocumentPositionParams from a documentUri , line number and character number
---@param documentUri string
---@param line integer
---@param character integer
---@return lsp.TextDocumentPositionParams
function M.TextDocumentPositionParams(documentUri, line, character)
  return {
    TextDocument = M.TextDocumentIdentifier(documentUri),
    Position = M.Position(line, character),
  }
end

-- function! s:DocumentationForSymbolRequest(xmlSig, assembly)
--     return {
--         \ 'XmlSig': a:xmlSig,
--         \ 'Assembly': a:assembly
--         \ }
-- endfunction

---Creates a DocumentationForSymbolRequest from the xmlSig and assembly strings
---@param xmlSig string
---@param assembly string
---@return FSharpDocumentationForSymbolRequest
function M.DocumentationForSymbolRequest(xmlSig, assembly)
  ---@type FSharpDocumentationForSymbolRequest
  local result =
  {
    XmlSig = xmlSig,
    Assembly = assembly,
  }
  return result
end

-- function! s:ProjectParms(projectUri)
--     return { 'Project': s:TextDocumentIdentifier(a:projectUri) }
-- endfunction


---creates a ProjectParms for fsharp/project call
---@param projectUri string
---@return FSharpProjectParams
function M.CreateFSharpProjectParams(projectUri)
  return {
    Project = M.TextDocumentIdentifier(projectUri),
  }
end

---Creates an FSharpWorkspacePeekRequest from a directory string path, the workspaceModePeekDeepLevel integer and excludedDirs list
---@param directory string
---@param deep integer
---@param excludedDirs string[]
---@return FSharpWorkspacePeekRequest
function M.CreateFSharpWorkspacePeekRequest(directory, deep, excludedDirs)
  return {
    Directory = vim.fs.normalize(directory),
    Deep = deep,
    ExcludedDirs = excludedDirs,
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

---Creates FSharpWorkspaceLoadParams from the string list of Project files to load given.
---@param files string[] -- project files only..
---@return FSharpWorkspaceLoadParams
function M.CreateFSharpWorkspaceLoadParams(files)
  local prm = {}
  for _, file in ipairs(files) do
    -- if stringEndsWith(file,"proj") then
    table.insert(prm, M.TextDocumentIdentifier(file))
    -- end
  end

  return { TextDocuments = prm }
end

---Calls the Lsp server endpoint with the method name, parameters
---@param method (string) LSP method name
---@param params table|nil Parameters to send to the server
function M.Call(method, params )
  ---@type lsp-handler
  local handler =
      function(responseError, result, handlerContext, config)
      local methodtoCall = M.Handlers[handlerContext.method]
      methodtoCall(responseError, result, handlerContext, config)
      end

  lsp.buf_request(0, method, params, handler)
end

function M.CallLspNotify(method, params)
  lsp.buf_notify(0, method, params)
end

-- function M.CallFSharpSignature(filePath, line, character cont)
--   return M.Call("fsharp/signature", M.TextDocumentPositionParams(filePath, line, character), cont)
-- end
--
-- function M.CallFSharpSignatureData(filePath, line, character, cont)
--   return M.Call("fsharp/signatureData", M.TextDocumentPositionParams(filePath, line, character), cont)
-- end
--
-- function M.CallFSharpLineLens(projectPath, cont)
--   return M.Call("fsharp/lineLens", M.CreateFSharpProjectParams(projectPath), cont)
-- end
--
-- function M.CallFSharpCompilerLocation(cont)
--   return M.Call("fsharp/compilerLocation", nil, cont or nil)
-- end

-- ---Calls "fsharp/compile" on the given project file
-- ---@param projectPath string
-- ---@param cont any
-- ---@return nil
-- function M.CallFSharpCompileOnProjectFile(projectPath, cont)
--   return M.Call("fsharp/compile", M.CreateFSharpProjectParams(projectPath), cont)
-- end
--
-- ---Calls "fsharp/workspacePeek" Lsp Endpoint of FsAutoComplete
-- ---@param directoryPath string
-- ---@param depth integer
-- ---@param excludedDirs string[]
-- ---@param cont any
-- ---@return nil
-- function M.CallFSharpWorkspacePeek(directoryPath, depth, excludedDirs, cont)
--   return M.Call("fsharp/workspacePeek", M.CreateFSharpWorkspacePeekRequest(directoryPath, depth, excludedDirs), cont)
-- end
--
-- ---Call to "fsharp/workspaceLoad"
-- ---@param projectFiles string[]  a string list of project files.
-- ---@param cont any
-- ---@return nil
-- function M.CallFSharpWorkspaceLoad(projectFiles, cont)
--   return M.Call("fsharp/workspaceLoad", M.CreateFSharpWorkspaceLoadParams(projectFiles), cont)
-- end
--
-- ---call to "fsharp/project" - which, after using projectPath to create an FSharpProjectParms, loads given project
-- ---@param projectPath string
-- ---@param cont integer
-- ---@return nil
-- function M.CallFSharpProject(projectPath, cont)
--   return M.Call("fsharp/project", M.CreateFSharpProjectParams(projectPath), cont)
-- end
--
-- function M.Fsdn(signature, cont)
--   return M.Call("fsharp/fsdn", M.FsdnRequest(signature), cont)
-- end
--
-- function M.F1Help(filePath, line, character, cont)
--   return M.Call("fsharp/f1Help", M.TextDocumentPositionParams(filePath, line, character), cont)
-- end
--
-- --- call to "fsharp/documentation"
-- --- first creates a TextDocumentPositionParams,
-- --- requests data about symbol at given position, used for InfoPanel
-- ---@param filePath string
-- ---@param line integer
-- ---@param character integer
-- ---@param cont any
-- ---@return nil
-- function M.CallFSharpDocumentation(filePath, line, character, cont)
--   return M.Call("fsharp/documentation", M.TextDocumentPositionParams(filePath, line, character), cont)
-- end
--
-- ---Calls "fsharp/documentationSymbol" Lsp endpoint on FsAutoComplete
-- ---creates a DocumentationForSymbolRequest then sends that request to FSAC
-- ---@param xmlSig string
-- ---@param assembly string
-- ---@param cont any
-- ---@return nil
-- function M.CallFSharpDocumentationSymbol(xmlSig, assembly, cont)
--   return M.Call("fsharp/documentationSymbol", M.DocumentationForSymbolRequest(xmlSig, assembly), cont)
-- end

--
function M.CallFSharpSignature(filePath, line, character )
  return M.Call("fsharp/signature", M.TextDocumentPositionParams(filePath, line, character) )
end

function M.CallFSharpSignatureData(filePath, line, character )
  return M.Call("fsharp/signatureData", M.TextDocumentPositionParams(filePath, line, character))
end

function M.CallFSharpLineLens(projectPath )
  return M.Call("fsharp/lineLens", M.CreateFSharpProjectParams(projectPath) )
end

function M.CallFSharpCompilerLocation()
  return M.Call("fsharp/compilerLocation", nil )
end

---Calls "fsharp/compile" on the given project file
---@param projectPath string
---@return nil
function M.CallFSharpCompileOnProjectFile(projectPath)
  return M.Call("fsharp/compile", M.CreateFSharpProjectParams(projectPath))
end

---Calls "fsharp/workspacePeek" Lsp Endpoint of FsAutoComplete
---@param directoryPath string
---@param depth integer
---@param excludedDirs string[]
---@return nil
function M.CallFSharpWorkspacePeek(directoryPath, depth, excludedDirs)
  return M.Call("fsharp/workspacePeek", M.CreateFSharpWorkspacePeekRequest(directoryPath, depth, excludedDirs))
end


---Call to "fsharp/workspaceLoad"
---@param projectFiles string[]  a string list of project files.
---@return nil
function M.CallFSharpWorkspaceLoad(projectFiles)
  return M.Call("fsharp/workspaceLoad", M.CreateFSharpWorkspaceLoadParams(projectFiles))
end

---call to "fsharp/project" - which, after using projectPath to create an FSharpProjectParms, loads given project
---@param projectPath string
---@return nil
function M.CallFSharpProject(projectPath)
  return M.Call("fsharp/project", M.CreateFSharpProjectParams(projectPath))
end

function M.Fsdn(signature)
  return M.Call("fsharp/fsdn", M.FsdnRequest(signature))
end

function M.F1Help(filePath, line, character)
  return M.Call("fsharp/f1Help", M.TextDocumentPositionParams(filePath, line, character))
end

--- call to "fsharp/documentation"
--- first creates a TextDocumentPositionParams,
--- requests data about symbol at given position, used for InfoPanel
---@param filePath string
---@param line integer
---@param character integer
---@return nil
function M.CallFSharpDocumentation(filePath, line, character)
  return M.Call("fsharp/documentation", M.TextDocumentPositionParams(filePath, line, character))
end

---Calls "fsharp/documentationSymbol" Lsp endpoint on FsAutoComplete
---creates a DocumentationForSymbolRequest then sends that request to FSAC
---@param xmlSig string
---@param assembly string
---@return nil
function M.CallFSharpDocumentationSymbol(xmlSig, assembly)
  return M.Call("fsharp/documentationSymbol", M.DocumentationForSymbolRequest(xmlSig, assembly))
end



---this should take the settings.FSharp table
---@param newSettingsTable _.lspconfig.settings.fsautocomplete.FSharp
function M.UpdateServerConfig(newSettingsTable)
  -- local input = vim.fn.input({ prompt = "Attach your debugger, to process " .. vim.inspect(vim.fn.getpid()) })
  local n = newSettingsTable or M.PassedInConfig.settings.FSharp or {}
  local defaults = M.DefaultServerSettings
  local oldMergedSettings = M.MergedConfig.settings.FSharp
  local mergedSettings = vim.tbl_deep_extend("keep", n, defaults)
  -- vim.notify("ionide settings.Fsharp config is " .. vim.inspect(n))
  if not M.PassedInConfig.settings.FSharp then
    M.PassedInConfig.settings.FSharp = mergedSettings
  else
    local newPassedIn = vim.tbl_deep_extend("keep", mergedSettings, oldMergedSettings)
    M.PassedInConfig.settings.FSharp = newPassedIn
  end
  local settings = { settings = { FSharp = mergedSettings } }
  -- vim.notify("ionide new passed in config is " .. vim.inspect(settings))
  local mergedConfig = vim.tbl_deep_extend("keep", M.PassedInConfig, M.MergedConfig)
  M.MergedConfig = mergedConfig

  -- vim.notify("ionide merged config is " .. vim.inspect(M.MergedConfig))
  M.CallLspNotify("workspace/didChangeConfiguration", settings)
end

---Loads the given projects list.
---@param projects string[] -- projects only
function M.LoadProjects(projects)
  if projects then
    for _, proj in ipairs(projects) do
      if proj then
        M.CallFSharpProject(proj)
      end
    end
  end
end

function M.ShowLoadedProjects()
  for proj, projInfo in pairs(M.Projects) do
    print("- " .. vim.fs.normalize(proj))
  end
end

function M.ReloadProjects()
  print("[Ionide] Reloading Projects")
  local foldersCount = #(vim.tbl_keys(M.Projects))
  if foldersCount > 0 then
    M.CallFSharpWorkspaceLoad(M.workspace_folders)
  else
    print("[Ionide] Workspace is empty")
  end
end

function M.OnFSProjSave()
  if vim.bo.ft == "fsharp_project" and M.AutomaticReloadWorkspace and M.AutomaticReloadWorkspace == true then
    vim.notify("[Ionide] fsharp project saved, reloading...")
    M.ReloadProjects()
  end
end

function M.ShowWorkspaceFolders()
  ---@type lsp.Client
  local client = vim.lsp.get_active_clients({
    bufnr = vim.api.nvim_get_current_buf(),
    name = "ionide"
  })[1]
  if client then
    local folders = client.workspace_folders or {}
    print("[Ionide] WorkspaceFolders: \n" .. vim.inspect(folders))
  else
    print("[Ionide] No ionide client found! \n")
  end
end

function M.ShowNvimSettings()
  print("[Ionide] NvimSettings: \n" .. vim.inspect(M.NvimSettings))
end

function M.ShowConfigs()
  -- print("[Ionide] Last passed in Config: \n" .. vim.inspect(M.PassedInConfig))
  print("[Ionide] Last final merged Config: \n" .. vim.inspect(M.MergedConfig))
  M.ShowNvimSettings()
  M.ShowWorkspaceFolders()
end


function M.LoadNvimSettings()
  local result = {}
  local s = {
    FsautocompleteCommand = { "fsautocomplete" },
    UseRecommendedServerConfig = false,
    AutomaticWorkspaceInit = true,
    AutomaticReloadWorkspace = true,
    ShowSignatureOnCursorMove = true,
    -- FsiCommand = "fsi.exe",
    FsiCommand = (function()
      -- if
      -- 	M.PassedInConfig.settings.FSharp.useSdkScripts == true
      -- 	or M.MergedConfig.settings.FSharp.useSdkScripts == true
      -- then
      return "dotnet fsi"
      -- else
      -- 	return "fsi.exe"
      -- end
    end)(),
    -- (function()
    --   local function determineFsiPath(useNetCore, ifNetFXUseAnyCpu)
    --     local pf, exe, arg, fsiExe
    --     if useNetCore == true then
    --       pf = os.getenv("ProgramW6432")
    --       if pf == nil or pf == "" then
    --         pf = os.getenv("ProgramFiles")
    --       end
    --       exe = pf .. "/dotnet/dotnet.exe"
    --       arg = "fsi"
    --       if not os.rename(exe, exe) then
    --         vim.notify("Could Not Find fsi.exe: " .. exe)
    --       end
    --       return exe .. " " .. arg
    --     else
    --       local function fsiExeName()
    --         local any = ifNetFXUseAnyCpu or true
    --         if any then
    --           return "fsiAnyCpu.exe"
    --           -- elseif runtime.architecture == "Arm64" then
    --           --   return "fsiArm64.exe"
    --         else
    --           return "fsi.exe"
    --         end
    --       end

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

    --       local function determineFsiRelativePath(name)
    --         local find = vim.fs.find({ name },
    --                 { path = vim.fn.getcwd(), upward = false, type = "file", limit = 1 })
    --         if vim.tbl_isempty(find) or find[1] == nil then
    --           return ""
    --         else
    --           return find[1]
    --         end
    --       end
    --
    --       local name = fsiExeName()
    --       local path = determineFsiRelativePath(name)
    --       if not path == "" then
    --         fsiExe = path
    --       else
    --         local fsbin = os.getenv("FSharpBinFolder")
    --         if fsbin == nil or fsbin == "" then
    --           local lastDitchEffortPath =
    --               vim.fs.find({ name },
    --                   {
    --                       path = "C:/Program Files (x86)/Microsoft Visual Studio/",
    --                       upward = false,
    --                       type = "file",
    --                       limit = 1
    --                   })
    --           if not lastDitchEffortPath then
    --             fsiExe = "Could not find FSI"
    --           else
    --             fsiExe = lastDitchEffortPath
    --           end
    --         else
    --           fsiExe = fsbin .. "/Tools/" .. name
    --         end
    --       end
    --       return fsiExe
    --     end
    --   end
    --
    --   local function shouldUseAnyCpu()
    --     local uname = vim.api.nvim_call_function("system", { "uname -m" })
    --     local architecture = uname:gsub("\n", "")
    --     if architecture == "" then
    --       local output = vim.api.nvim_call_function("system", { "cmd /c echo %PROCESSOR_ARCHITECTURE%" })
    --       architecture = output:gsub("\n", "")
    --     end
    --     if string.match(architecture, "64") then
    --       return true
    --     else
    --       return false
    --     end
    --   end
    --
    --   local useSdkScripts = false
    --   if M.DefaultServerSettings then
    --     local ds = M.DefaultServerSettings
    --     if ds.useSdkScripts then
    --       useSdkScripts = ds.useSdkScripts
    --     end
    --   end
    --   if not M.PassedInConfig then
    --     M["PassedInConfig"] = {}
    --   end
    --   if M.PassedInConfig.settings then
    --     if M.PassedInConfig.settings.FSharp then
    --       if M.PassedInConfig.settings.FSharp.useSdkScripts then
    --         useSdkScripts = M.PassedInConfig.settings.FSharp.useSdkScripts
    --       end
    --     end
    --   end
    --
    --   local useAnyCpu = shouldUseAnyCpu()
    --   return determineFsiPath(useSdkScripts, useAnyCpu)
    -- end)(),
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
    if not result[k] then
      result[k] = v
    end
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

  M.CallFSharpSignature(vim.fn.expand("%:p"), vim.cmd.line(".") - 1, vim.cmd.col(".") - 1, cbShowSignature)
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
  -- if M.LspCodelens == true or M.LspCodelens == 1 then

  autocmd({ "LspAttach" }, {
    desc = "FSharp clear code lens on attach ",
    group = grp("FSharp_ClearCodeLens", { clear = true }),
    pattern = "*.fs,*.fsi,*.fsx",
    callback = function(args)
      -- args.data.client_id
      vim.defer_fn(function()
        vim.notify("clearing lsp codelens and refreshing")
        vim.lsp.codelens.clear()
        vim.lsp.codelens.refresh()
      end, 7000)
      -- vim.lsp.codelens.clear()
      -- vim.lsp.codelens.refresh()
    end,
  })

  autocmd({ "LspAttach", "BufEnter", "BufWritePost", "InsertLeave" }, {
    desc = "FSharp Auto refresh code lens ",
    group = grp("FSharp_AutoRefreshCodeLens", { clear = true }),
    pattern = "*.fs,*.fsi,*.fsx",
    callback = function(arg)
      vim.defer_fn(function()
        vim.lsp.codelens.refresh()
        -- vim.notify("lsp codelens refreshing")
      end, 2000)
    end,
  })
end

-- end

autocmd({ "CursorHold,InsertLeave" }, {
  desc = "URL Highlighting",
  group = grp("FSharp_HighlightUrl", { clear = true }),
  pattern = "*.fs,*.fsi,*.fsx,*.fsproj",
  callback = function()
    vim.defer_fn(function()
      M.OnCursorMove()
      -- vim.notify("lsp codelens refreshing")
    end, 1000)
  end,
})

function M.Initialize()
  if not vim.fn.has("nvim") then
    print("WARNING - This version of Ionide is only for NeoVim. please try Ionide/Ionide-Vim instead. ")
    return
  end

  print("Ionide Initializing")
  print("Ionide calling updateServerConfig...")
  M.UpdateServerConfig()
  print("Ionide calling SetKeymaps...")
  M.SetKeymaps()
  print("Ionide calling registerAutocmds...")
  M.RegisterAutocmds()
  print("Ionide Initialized")
end

function M.GitFirstRootDir(n)
  -- local preRoot
  -- preRoot = util.find_git_ancestor(n)
  -- preRoot = preRoot or util.root_pattern("*.sln")(n)
  -- preRoot = preRoot or util.root_pattern("*.fsproj")(n)
  -- preRoot = preRoot or util.root_pattern("*.fsx")(n)
  --  local peek = M.Call("fsharp/workspacePeek",M.WorkspacePeekRequest( preRoot,M.MergedConfig.settings.FSharp.workspaceModePeekDeepLevel,{}),os.time())
  --
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

  ---@type lspconfig.options.fsautocomplete
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
    -- root_dir = local_root_dir,M.GitFirstRootDir(n)
    root_dir = M.GitFirstRootDir,
    -- root_dir = util.root_pattern("*.sln"),
  }
  -- vim.notify("ionide default settings are : " .. vim.inspect(result))
  return result
end

-- M.Manager = nil
function M.AutoStartIfNeeded(config)
  local auto_setup = (M.NvimSettings.LspAutoSetup == 1)
  if auto_setup and not (config.autostart == false) then
    M.Autostart()
  end
end

function M.DelegateToLspConfig(config)
  local lspconfig = require("lspconfig")
  local configs = require("lspconfig.configs")
  if not configs["ionide"] then
    configs["ionide"] = {
      default_config = config,
      docs = {
        description = [[ https://github.com/willehrendreich/Ionide-vim ]],
      },
    }
  end
  -- M.UpdateServerConfig(config or M.MergedConfig)
  lspconfig.ionide.setup(config or M.MergedConfig)
end

--- ftplugin section ---
vim.filetype.add({
  extension = {
    fsproj = function(_, _)
      return "fsharp_project",
          function(bufnr)
            vim.bo[bufnr].syn = "xml"
            vim.bo[bufnr].ro = false
            vim.b[bufnr].readonly = false
            vim.bo[bufnr].commentstring = "<!--%s-->"
            -- vim.bo[bufnr].comments = "<!--,e:-->"
            vim.opt_local.foldlevelstart = 99
            vim.w.fdm = "syntax"
          end
    end,
  },
})

vim.filetype.add({
  extension = {
    fs = function(path, bufnr)
      return "fsharp",
          function(bufnr)
            if not vim.g.filetype_fs then
              vim.g["filetype_fs"] = "fsharp"
            end
            if not vim.g.filetype_fs == "fsharp" then
              vim.g["filetype_fs"] = "fsharp"
            end
            vim.w.fdm = "syntax"
            -- comment settings
            vim.bo[bufnr].formatoptions = "croql"
            -- vim.bo[bufnr].commentstring = "(*%s*)"
            vim.bo[bufnr].commentstring = "//%s"
            vim.bo[bufnr].comments = [[s0:*\ -,m0:*\ \ ,ex0:*),s1:(*,mb:*,ex:*),:\/\/\/,:\/\/]]
          end
    end,
    fsx = function(path, bufnr)
      return "fsharp",
          function(bufnr)
            if not vim.g.filetype_fs then
              vim.g["filetype_fsx"] = "fsharp"
            end
            if not vim.g.filetype_fs == "fsharp" then
              vim.g["filetype_fsx"] = "fsharp"
            end
            vim.w.fdm = "syntax"
            -- comment settings
            vim.bo[bufnr].formatoptions = "croql"
            vim.bo[bufnr].commentstring = "//%s"
            -- vim.bo[bufnr].commentstring = "(*%s*)"
            vim.bo[bufnr].comments = [[s0:*\ -,m0:*\ \ ,ex0:*),s1:(*,mb:*,ex:*),:\/\/\/,:\/\/]]
          end
    end,
  },
})

-- vim.api.nvim_create_autocmd("BufWritePost", {
--     pattern = "*.fsproj",
--     desc = "FSharp Auto refresh on project save",
--     group = vim.api.nvim_create_augroup("FSharpLCFsProj", { clear = true }),
--     callback = function() M.OnFSProjSave() end
-- })

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
  validate({
    cmd = { config.cmd, "t", true },
    root_dir = { config.root_dir, "f", true },
    filetypes = { config.filetypes, "t", true },
    on_attach = { config.on_attach, "f", true },
    on_new_config = { config.on_new_config, "f", true },
  })

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
    ---@type string
    local root_dir = get_root_dir(api.nvim_buf_get_name(0), api.nvim_get_current_buf())
    if not root_dir then
      root_dir = util.path.dirname(api.nvim_buf_get_name(0)) or ""
    end
    if not root_dir or root_dir == "" then
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
    ---@type lspconfig.options.fsautocomplete
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

  local manager = util.server_per_root_dir_manager(function(_root_dir)
    return M.MakeConfig(_root_dir)
  end)

  function manager.try_add(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if api.nvim_buf_get_option(bufnr, "buftype") == "nofile" then
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
    local buftype = api.nvim_buf_get_option(bufnr, "filetype")
    if buftype == "fsharp" then
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
    M.AutoStartIfNeeded(config)
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
  if vim.fn.has("nvim") then
    if M.NvimSettings.FsiKeymap == "vscode" then
      M.NvimSettings.FsiKeymapSend = "<M-cr>"
      M.NvimSettings.FsiKeymapToggle = "<M-@>"
    elseif M.NvimSettings.FsiKeymap == "vim-fsharp" then
      M.NvimSettings.FsiKeymapSend = "<leader>i"
      M.NvimSettings.FsiKeymapToggle = "<leader>e"
    elseif M.NvimSettings.FsiKeymap == "custom" then
      M.NvimSettings.FsiKeymap = "none"
      if not M.NvimSettings.FsiKeymapSend then
        vim.cmd.echoerr(
          "FsiKeymapSend not set. good luck with that I dont have a nice way to change it yet. sorry. "
        )
      elseif not M.NvimSettings.FsiKeymapToggle then
        vim.cmd.echoerr(
          "FsiKeymapToggle not set. good luck with that I dont have a nice way to change it yet. sorry. "
        )
      else
        M.NvimSettings.FsiKeymap = "custom"
      end
    end
  else
    vim.notify("I'm sorry I don't support regular vim, try ionide/ionide-vim instead")
  end
end

function M.setup(config)
  -- vim.notify("[Ionide] Arg given to setup call : \n" .. vim.inspect(config or {}))
  M.PassedInConfig = vim.tbl_deep_extend("force", M.PassedInConfig, config or {})
  -- M.NvimSettings = M.LoadNvimSettings()
  -- M.DefaultServerSettings = M.LoadDefaultServerSettings()

  M.DefaultLspConfig = M.GetDefaultLspConfig()

  M.InitializeDefaultFsiKeymapSettings()
  M.MergedConfig = vim.tbl_deep_extend("keep", M.PassedInConfig, M.DefaultLspConfig)
  if lspconfig_is_present then
    return M.DelegateToLspConfig(M.MergedConfig)
  end
  return create_manager(M.MergedConfig)
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
  if vim.fn.has("nvim") then
    vim.fn.win_gotoid(id)
  else
    vim.fn.timer_start(1, function()
      vimReturnFocus(id)
    end, {})
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
  local cmd = M.NvimSettings.FsiCommand or "dotnet fsi"
  local ep = M.MergedConfig.settings.FSharp.fsiExtraParameters or {}
  for _, x in pairs(ep) do
    cmd = cmd .. " " .. x
  end
  return cmd
end

function M.OpenFsi(returnFocus)
  -- vim.notify("openfsi return focus is " .. tostring(returnFocus))
  local isNeovim = vim.fn.has("nvim")
  --"     if bufwinid(s:fsi_buffer) <= 0
  if vim.fn.bufwinid(fsiBuffer) <= 0 then
    -- vim.notify("fsiBuffer id is " .. tostring(fsiBuffer))
    --"         let fsi_command = s:get_fsi_command()
    local cmd = getFsiCommand()
    --"         if exists('*termopen') || exists('*term_start')
    if vim.fn.exists("*termopen") == true or vim.fn.exists("*term_start") then
      --"             let current_win = win_getid()
      local currentWin = vim.fn.win_getid()
      --"             execute g:fsharp#fsi_window_command
      vim.fn.execute(M.FsiWindowCommand or "botright 10new")
      --"             if s:fsi_width  > 0 | execute 'vertical resize' s:fsi_width | endif
      if fsiWidth > 0 then
        vim.fn.execute("vertical resize " .. fsiWidth)
      end
      --"             if s:fsi_height > 0 | execute 'resize' s:fsi_height | endif

      if fsiHeight > 0 then
        vim.fn.execute("resize " .. fsiHeight)
      end
      --"             " if window is closed but FSI is still alive then reuse it
      --"             if s:fsi_buffer >= 0 && bufexists(str2nr(s:fsi_buffer))
      if fsiBuffer >= 0 and vim.fn.bufexists(fsiBuffer) then
        --"                 exec 'b' s:fsi_buffer
        vim.fn.cmd("b" .. tostring(fsiBuffer))
        --"                 normal G
        vim.cmd("normal G")
        --"                 if !has('nvim') && mode() == 'n' | execute "normal A" | endif
        if not isNeovim and vim.api.nvim_get_mode()[1] == "n" then
          vim.cmd("normal A")
        end
        --"                 if a:returnFocus | call s:win_gotoid_safe(current_win) | endif
        if returnFocus then
          winGoToIdSafe(currentWin)
        end
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
          term_finish = "close",
        }
        --"                 \ "term_name": "F# Interactive",

        --"                 \ "curwin": 1,

        --"                 \ "term_finish": "close"

        --"                 \ }

        --"                 let s:fsi_buffer = term_start(fsi_command, options)
        fsiBuffer = vim.fn("term_start(" .. M.NvimSettings.FsiCommand .. ", " .. vim.inspect(options) .. ")")
        --"                 if s:fsi_buffer != 0
        if fsiBuffer ~= 0 then
          --"                     if exists('*term_setkill') | call term_setkill(s:fsi_buffer, "term") | endif
          if vim.fn.exists("*term_setkill") == true then
            vim.fn("term_setkill(" .. fsiBuffer .. [["term"]])
          end
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
      if returnFocus then
        winGoToIdSafe(currentWin)
      end
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
    fsiWidth = vim.fn.winwidth(tonumber(vim.fn.expand("%")) or 0)
    fsiHeight = vim.fn.winheight(tonumber(vim.fn.expand("%")) or 0)
    vim.cmd.close()
    vim.fn.win_gotoid(curWin)
  else
    M.OpenFsi()
  end
end

function M.GetVisualSelection(keepSelectionIfNotInBlockMode, advanceCursorOneLine, debugNotify)
  local line_start, column_start
  local line_end, column_end
  -- if debugNotify is true, use vim.notify to show debug info.
  debugNotify = debugNotify or false
  -- keep selection defaults to false, but if true the selection will
  -- be reinstated after it's cleared to set '> and '<
  -- only relevant in visual or visual line mode, block always keeps selection.
  keepSelectionIfNotInBlockMode = keepSelectionIfNotInBlockMode or false
  -- advance cursor one line defaults to true, but is turned off for
  -- visual block mode regardless.
  advanceCursorOneLine = (function()
    if keepSelectionIfNotInBlockMode == true then
      return false
    else
      return advanceCursorOneLine or true
    end
  end)()

  if vim.fn.visualmode() == "\22" then
    line_start, column_start = unpack(vim.fn.getpos("v"), 2)
    line_end, column_end = unpack(vim.fn.getpos("."), 2)
  else
    -- if not in visual block mode then i want to escape to normal mode.
    -- if this isn't done here, then the '< and '> do not get set,
    -- and the selection will only be whatever was LAST selected.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), "x", true)
    line_start, column_start = unpack(vim.fn.getpos("'<"), 2)
    line_end, column_end = unpack(vim.fn.getpos("'>"), 2)
  end
  if column_start > column_end then
    column_start, column_end = column_end, column_start
    if debugNotify == true then
      vim.notify(
        "switching column start and end, \nWas "
        .. column_end
        .. ","
        .. column_start
        .. "\nNow "
        .. column_start
        .. ","
        .. column_end
      )
    end
  end
  if line_start > line_end then
    line_start, line_end = line_end, line_start
    if debugNotify == true then
      vim.notify(
        "switching line start and end, \nWas "
        .. line_end
        .. ","
        .. line_start
        .. "\nNow "
        .. line_start
        .. ","
        .. line_end
      )
    end
  end
  if vim.g.selection == "exclusive" then
    column_end = column_end - 1 -- Needed to remove the last character to make it match the visual selection
  end
  if debugNotify == true then
    vim.notify(
      "vim.fn.visualmode(): "
      .. vim.fn.visualmode()
      .. "\nsel start "
      .. vim.inspect(line_start)
      .. " "
      .. vim.inspect(column_start)
      .. "\nSel end "
      .. vim.inspect(line_end)
      .. " "
      .. vim.inspect(column_end)
    )
  end
  local n_lines = math.abs(line_end - line_start) + 1
  local lines = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
  if #lines == 0 then
    return { "" }
  end
  if vim.fn.visualmode() == "\22" then
    -- this is what actually sets the lines to only what is found between start and end columns
    for i = 1, #lines do
      lines[i] = string.sub(lines[i], column_start, column_end)
    end
  else
    lines[1] = string.sub(lines[1], column_start, -1)
    if n_lines == 1 then
      lines[n_lines] = string.sub(lines[n_lines], 1, column_end - column_start + 1)
    else
      lines[n_lines] = string.sub(lines[n_lines], 1, column_end)
    end
    -- if advanceCursorOneLine == true, then i do want the cursor to advance once.
    if advanceCursorOneLine == true then
      if debugNotify == true then
        vim.notify(
          "advancing cursor one line past the end of the selection to line " .. vim.inspect(line_end + 1)
        )
      end
      vim.api.nvim_win_set_cursor(0, { line_end + 1, 0 })
    end

    if keepSelectionIfNotInBlockMode then
      vim.api.nvim_feedkeys("gv", "n", true)
    end
  end
  if debugNotify == true then
    vim.notify(table.concat(lines, "\n"))
  end
  return lines -- use this return if you want an array of text lines
  -- return table.concat(lines, "\n") -- use this return instead if you need a text block
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
--

---Quit current fsi
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
  -- vim.notify("[Ionide] Text being sent to FSI:\n" .. text)
  local openResult = M.OpenFsi(not M.FsiFocusOnSend or false)
  -- vim.notify("[Ionide] result of openfsi function is " .. vim.inspect(openResult))
  if not openResult then
    openResult = 1
    -- vim.notify("[Ionide] changing result to 1 and hoping for the best. lol. " .. vim.inspect(openResult))
  end

  if openResult > 0 then
    if vim.fn.has("nvim") then
      vim.fn.chansend(fsiJob, text .. "\n" .. ";;" .. "\n")
    else
      vim.api.nvim_call_function("term_sendkeys", { fsiBuffer, text .. "\\<cr>" .. ";;" .. "\\<cr>" })
      vim.api.nvim_call_function("term_wait", { fsiBuffer })
    end
  end
end


function M.GetCompleteBuffer()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 1, -1, false)
end

function M.SendSelectionToFsi()
  -- vim.cmd(':normal' .. vim.fn.len(lines) .. 'j')
  local lines = M.GetVisualSelection()

  -- vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), 'x', true)
  -- vim.cmd(':normal' .. ' j')
  -- vim.cmd('normal' .. vim.fn.len(lines) .. 'j')
  local text = vim.fn.join(lines, "\n")
  -- vim.notify("fsi send selection " .. text)
  M.SendFsi(text)

  -- local line_end, _ = unpack(vim.fn.getpos("'>"), 2)

  -- vim.cmd 'normal j'

  -- vim.cmd(':normal' .. ' j')
  -- vim.api.nvim_win_set_cursor(0, { line_end + 1, 0 })

  -- vim.cmd(':normal' .. vim.fn.len(lines) .. 'j')
end

function M.SendLineToFsi()
  local text = vim.api.nvim_get_current_line()
  local line, _ = unpack(vim.fn.getpos("."), 2)
  vim.api.nvim_win_set_cursor(0, { line + 1, 0 })
  -- vim.notify("fsi send line " .. text)
  M.SendFsi(text)
  -- vim.cmd 'normal j'
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
  vim.keymap.set("v", send, function()
    M.SendSelectionToFsi()
  end, { silent = false })
  vim.keymap.set("n", send, function()
    -- vim.notify("[Ionide] jsut pressed " .. send .. " in normal mode. expecting to send line to fsi. ")
    M.SendLineToFsi()
  end, { silent = false })
  vim.keymap.set("n", toggle, function()
    M.ToggleFsi()
  end, { silent = false })
  vim.keymap.set("t", toggle, function()
    M.ToggleFsi()
  end, { silent = false })
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

uc("IonideCompilerLocation", function () M.CallFSharpCompilerLocation() end, {  desc = "Get compiler location data from FSAC" })

uc("IonideSendFSI", M.SendFsi, { desc = "Ionide - Send text to FSharp Interactive" })
uc("IonideToggleFSI", M.ToggleFsi, { desc = "Ionide - Toggle FSharp Interactive" })
uc("IonideQuitFSI", M.QuitFsi, { desc = "Ionide - Quit FSharp Interactive" })
uc("IonideResetFSI", M.ResetFsi, { desc = "Ionide - Reset FSharp Interactive" })

uc("IonideShowConfigs", M.ShowConfigs, {})
uc("IonideShowWorkspaceFolders", M.ShowWorkspaceFolders, {})
uc("IonideLoadProjects", function(opts)
  if type(opts.fargs) == "string" then
    local projTable = { opts.fargs }
    M.LoadProjects(projTable)
  elseif type(opts.fargs) == "table" then
    local projects = opts.faargs
    M.LoadProjects(projects)
  elseif opts.nargs > 1 then
    local projects = {}
    for _, proj in ipairs(opts.fargs) do
      table.insert(projects, proj)
    end
    M.LoadProjects(projects)
  else
    print(vim.inspect(opts))
  end
end, {
})

uc("IonideShowLoadedProjects", M.ShowLoadedProjects, {})
uc("IonideShowNvimSettings", M.ShowNvimSettings, {})
uc("IonideShowAllLoadedProjectInfo", function() vim.notify(vim.inspect(M.Projects)) end, {desc ="Show all currently loaded Project Info, as far as Neovim knows or cares"})
uc("IonideShowAllLoadedWorkspaceFolders", function() vim.notify(vim.inspect(M.workspace_folders)) end, {desc ="Show all currently loaded workspace folders, as far as Neovim knows or cares"})
uc("IonideWorkspacePeek", function() M.CallFSharpWorkspacePeek( vim.fn.getcwd(), 4, {}) end,
  { desc = "Request a workspace peek from Lsp" })

return M
