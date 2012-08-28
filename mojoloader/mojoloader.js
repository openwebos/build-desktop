// @@@LICENSE
//
//      Copyright (c) 2009-2012 Hewlett-Packard Development Company, L.P.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// LICENSE@@@

/*globals PalmSystem palmGetResource _mojoRequire palmRequire */
/*jslint evil: true */

var fs;

if (typeof process !== 'undefined') {
	fs = require('fs');
}

if (typeof MojoLoader === 'undefined')
{
	var MojoLoader =
	{
		/*
		 * The list of paths we use to search for a given library/framework.
		 * We search the system install paths first, and if that fails, look in a local path
		 * within the given library.
		 */
		_palmPath: [ "/usr/palm/frameworks/", "/usr/palm/frameworks/private/", "frameworks/" ],
		_publicPath: [ "/usr/palm/frameworks/", "frameworks/" ],
		_tritonPath: [ "" ],
		_path: undefined,
	
		_loaded: {},
	
		_root: this,
	
		/*
		 * Define the environment of the loader.
		 */
		_env: (typeof document !== "undefined" ? "browser" : "triton"),
		_isPalm: (typeof PalmSystem === "undefined" || PalmSystem.identifier.indexOf("com.palm.") === 0),
	
		/*
		 * The current root of this module (the current directory by default)
		 */
		root: "./",

		/*
		 * Specify what libraries we require.  The function takes the following form:
		 *
		 *   var libs = MojoLoader.require({ name: "mylibrary", version: "1.0" }, { name: "Mojo.UI", submission: "123" });
		 *   libs["mylibrary"].doit();
		 * 
		 * The function takes a list of name/versions for each framework we require and returns an object which has a 
		 * property for the exports of each loaded framework.
		 */
		require: function()
		{
			var libs = {};

			// Foreach library to load ...
			var alen = arguments.length;
			for (var a = 0; a < alen; a++)
			{
				// Split out the library name and version
				var arg = arguments[a];
				var name = arg.name;
				if (!name)
				{
					throw new Error("Missing library name");
				}
				var version = this._getVersion(arg);
				if (!version)
				{
					throw new Error("Library " + name + ": Missing version");
				}

				// Dont load library if its already loaded
				var library = this._loaded[name];
				if (!library)
				{
					this._loaded[name] = library = {
						name: name,
						version: version,
						versionNumber: arg.version,
						exports: {},
						loaded: false,
						pending: []
					};
					// Load the library into a container
					this._loadLibraryIntoContainer(library);
				}
				// If library is loaded, make sure its the same version we want
				else if (library.version != version)
				{
					throw new Error("Library " + name + ": Dependency conflict (want '" + version + "' but already loaded '" + library.version + "')");
				}

				// Get the library export object
				libs[name] = library.exports;

				if (library.exports.__setGlobal__) {
					library.exports.__setGlobal__(this._root, this._newLoader(library.root));
				}
				if (library.exports.onLoad) {
					library.exports.onLoad();
				}
			}

			// They're all loaded
			return libs;
		},
		
		locate: function(arg)
		{
			var info = this._locate(arg.name, this._getVersion(arg));
			if (info)
			{
				return info.base;
			}
			else
			{
				return undefined;
			}
		},
		
		_loadFileNode: function(pathToFile) {
			return fs.readFileSync(pathToFile, "utf8");
		},
		
		_loadFileMojoOrTriton: function(pathToFile) {
			return palmGetResource(pathToFile, false);
		},
		
		_locate: function(name, version)
		{
			var path = this._path;

			// Work out the path to the library on the file system
			for (var pathidx = 0; pathidx < path.length; pathidx++)
			{
				var base = path[pathidx] + name + "/";
				var vbase = base + version + "/";
				try
				{
					var manifestPath = vbase + "manifest.json";
					var manifestSource = this._loadFile(manifestPath);
					var manifest = JSON.parse(manifestSource);
					if (manifest)
					{	
						return { base: vbase, manifest: manifest };
					}
				}
				catch (_)
				{
					//console.log(_);
				}
			}
			
			return undefined;
		},
	
		_getVersion: function(arg)
		{
			return "version/" + arg.version;
		},

		_loadLibraryUsingEval: function(library, base, manifest)
		{
			var jbase, sources, slen;
			var lname = "__MojoFramework_" + library.name;

			/* "concatenated.js" is created during the build and contains the
			 * library in a single file. If that file does not exist MojoLoader
			 * must read the manifest and concatenate the file contents itself.
			 */
			var data = palmGetResource(base + "concatenated.js");

			if (data === null) {
				data = "this._root[lname] = function(MojoLoader, exports, root) {\n";
				jbase = base + "javascript/";
				sources = manifest.files.javascript;
				slen = sources.length;

				for (var i = 0; i < slen; i++)
				{
					data += ("\n\n//@ sourceURL=" + library.name + "/" + sources[i] + "\n\n");
					data += palmGetResource(jbase + sources[i]);
				}
				data += "\n}";
			}

			eval(data);
			this._root[lname](this._newLoader(base), library.exports, this._root);
		},
		
		_loadLibrary: function(library, base, manifest)
		{
			var jbase = base + "javascript/";
			var paths = [];
			var sources = manifest.files.javascript;
			var slen = sources.length;
			for (var i = 0; i < slen; i++)
			{
				paths.push(jbase + sources[i]);
			}
			library.exports = this._propogateGlobals(this._require(this._newLoader(base), paths), this._root).exports;
		},
		
		_propogateGlobals: function(to, from)
		{
			var syms = [ 
				/* Common */ 	"console", "palmGetResource", "setTimeout", "clearTimeout", "setInterval", "clearInterval",
				/* Triton */	"getenv", "readInput", "quit", "include", "_mojoRequire", "webOS", "palmPutResource",
				/* Mojo */		"XMLHttpRequest", "palmRequire", "palmInclude", "PalmServiceBridge", "PalmSystem"
			];
			var len = syms.length;
			for (var i = 0; i < len; i++)
			{
				var sym = syms[i];
				if (sym in from && !(sym in to))
				{
					to[sym] = from[sym];
				}
			}
			return to;
		},

		builtinLibName: function(name, version) {
			return [
				"palm",
				name.replace('.', '_'),
				"Version",
				version.replace('.', '_')].join('');
		},

		_loadBuiltin: function(library, base) {
			var bName = this.builtinLibName(library.name, library.versionNumber);
			if (this._root[bName]) {
				console.log("Using builtin: " + bName);
				library.exports = this._root[bName];
				library.root = base;
				return true;
			}
			else {
				return false;
			}
		},
		
		_loadNodeBuiltin: function(library, base) {
			var bName = this.builtinLibName(library.name, library.versionNumber);
			if (global[bName]) {
				console.log("Using builtin: " + bName);
				library.exports = global[bName];
				library.root = base;
				return true;
			}
			else {
				return false;
			}
		},

		/*
		 * Search the path and load the library into a container.
		 * The container (an iframe) is used to isolate the global library from the rest
		 * The library executes the callback once its has been loaded.
		 */
		_loadLibraryIntoContainer: function(library)
		{
			var info = this._locate(library.name, library.version);

			if (this.isNode() && this._loadNodeBuiltin(library, info.base)) {
				return library;
			}
			else if (!this.isNode() && this._loadBuiltin(library, info.base)) {
				return library;
			}
			else {
				if (info)
				{
					try
					{
						return this._loadLibrary(library, info.base, info.manifest);
					}
					catch (e)
					{
						console.log(e.stack || e);
					}
				}
				throw new Error("Failed to load library '" + library.name + " " + library.version + "' paths '" + (this._path[0] !== "" ? this._path.join(",") : "<command line>") +  "'");
			}
		},

		_newLoader: function(root)
		{
			var self = this;
			return {
				root: root,

				locate: function()
				{
					return self.locate.apply(self, arguments);
				},

				require: function()
				{
					return self.require.apply(self, arguments);
				},
			
				override: function()
				{
					return self.override.apply(self, arguments);
				}
			};
		},
		
		_selectLoader: function()
		{
			if (typeof _mojoRequire !== "undefined") 
			{
				this._require = _mojoRequire;
				this._loadFile = this._loadFileMojoOrTriton;
			}
			else if (typeof palmRequire !== "undefined")
			{
				this._require = palmRequire;
				this._loadFile = this._loadFileMojoOrTriton;
			}
			else if (typeof require !== "undefined")
			{
				var webOS = require('webos');
				var sys = require('sys');
				function nodeRequire (loader, filesArary) {
				    return webOS.require(require, loader, filesArary);
				}
				this._require = nodeRequire;
				this._loadFile = this._loadFileNode;
			}
			else
			{
				if (this._env == 'browser' && typeof palmGetResource === "undefined") 
				{
					palmGetResource = function(pathToResource) 
					{
						var req = new XMLHttpRequest();
						req.open('GET', pathToResource + "?palmGetResource=true", false); 
						req.send(null);
						if (req.status >= 200 && req.status < 300) {
							return req.responseText;
						}
						return undefined;
					};
				}
				this._loadFile = this._loadFileMojoOrTriton;
				this._loadLibrary = this._loadLibraryUsingEval;
			}
		},
		
		runtime: function() {
			if (typeof process !== "undefined") {
				return "node";
			}
			
			if (typeof webOS !== "undefined") {
				return "triton";
			}
			
			return "browser";
		},
		
		isBrowser: function() {
			return this.runtime() === "browser";
		},
		
		isTriton: function() {
			return this.runtime() === "triton";
		},
		
		isNode: function() {
			return this.runtime() === "node";
		}
	};
	MojoLoader._selectLoader();
	MojoLoader._path = MojoLoader._isPalm ? MojoLoader._palmPath : MojoLoader._publicPath;
	if (!MojoLoader.isBrowser()) {
		var BEDLAM_ROOT;
		if (MojoLoader.isNode()) {
		 	BEDLAM_ROOT = process.env.BEDLAM_ROOT;
		} else {
		 	BEDLAM_ROOT = getenv("BEDLAM_ROOT");
		}
		if(BEDLAM_ROOT) {
			var path = MojoLoader._path;
			var count = path.length;
			var i;
			for(i = 0; i < count; ++i) {
				path[i] = path[i].replace("/usr", BEDLAM_ROOT);
			}
		}
	}
	if (typeof exports !== 'undefined') {
		var propertyName;
		for (propertyName in MojoLoader) {
			if (MojoLoader.hasOwnProperty(propertyName)) {
				exports[propertyName] = MojoLoader[propertyName];
			}
		}
	}
} // end if (!MojoLoader)
