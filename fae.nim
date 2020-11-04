import 
  packages/nim-sgregex/sgregex,
  std/exitprocs,
  parseopt,
  os,
  terminal,
  strutils,
  times

type
  StringBounds = array[0..1, int]
  FaeOptions = object
    regex: string
    insensitive: bool
    recursive: bool
    filter: string
    substitute: string
    directory: string
    apply: bool
    test: bool
    silent: bool

addExitProc(resetAttributes)

const version = "1.0.0"

const usage = """FAE v""" & version & """ - Find & Edit Utility
  (c) 2020 Fabio Cevasco

  Usage:
    fae <pattern> <replacement> [option1 option2 ...]

  Where:
    <pattern>           A regular expression to search for
    <replacement>      An optional replacement string

  Options:
    -a, --apply         Substitute all occurrences of <pattern> with <replacement> in all files
                        without asking for confirmation.
    -d, --directory     Search in the specified directory (default: .)
    -f, --filter        Specify a regular expression to filter file paths.
    -h, --help          Display this message.
    -i, --insensitive   Case-insensitive matching.
    -r, --recursive     Search directories recursively.
    -s, --silent        Do not display matches.
    -t, --test          Do not perform substitutions, just print results.
    -v, --version       Display the program version.
"""

proc flags(options: FaeOptions): string = 
  if options.insensitive:
    "i"
  else:
    ""
    
proc matchBounds(str, expr: string, start = 0, options: FaeOptions): StringBounds = 
  if start > str.len-2:
    return [-1, -1]
  let s = str.substr(start)
  let c = s.search(expr, options.flags)
  if c[0].len > 0:
    let match = c[0]
    let mstart = strutils.find(s, match)
    if mstart < 0:
      return [-1, -1]
    let mfinish = mstart + match.len-1
    result = [mstart+start, mfinish+start]
  else:
    result = [-1, -1]

proc matchBoundsRec(str, regex: string, start = 0, matches: var seq[StringBounds], options: FaeOptions) =
  let match = str.matchBounds(regex, start, options)
  if match[0] >= 0:
    matches.add(match)
    matchBoundsRec(str, regex, match[1]+1, matches, options)

proc replace(str, regex: string, substitute: var string, start = 0, options: FaeOptions): string =
  return sgregex.replace(str, regex, substitute, options.flags)

proc displayMatch(str: string, start, finish: int, color = fgYellow, lineN: int, silent = false) =
  if silent:
    return
  let max_extra_chars = 20
  let context_start = max(start-max_extra_chars, 0)
  let context_finish = min(finish+max_extra_chars, str.len)
  let match: string = str.substr(start, finish)
  var context: string = str.substr(context_start, context_finish)
  if context_start > 2:
    context = "..." & context
  if context_finish < str.len + 3:
    context = context & "..."
  let match_context_start:int = strutils.find(context, match, start-context_start)
  let match_context_finish:int = match_context_start+match.len
  stdout.write(" ")
  setForegroundColor(color, true)
  stdout.write(lineN)
  resetAttributes()
  stdout.write(": ")
  for i in 0 .. (context.len):
    if i == match_context_start:
      setForegroundColor(color, true)
    if i < context.len:
      stdout.write(context[i])
    if i == match_context_finish:
      resetAttributes()
  stdout.write("\p")

proc displayFile(str: string, silent = false) =
  if silent:
    return
  stdout.write "["
  setForegroundColor(fgYellow, true)
  for i in 0..str.len-1:
    stdout.write(str[i])
  resetAttributes()
  stdout.write "]"

proc confirm(msg: string): bool = 
  stdout.write(msg)
  var answer = stdin.readLine()
  if answer.match("y(es)?", "i"):
    return true
  elif answer.match("n(o)?", "i"):
    return false
  else:
    return confirm(msg)

proc processFile(f:string, options: FaeOptions): array[0..1, int] =
  var matchesN = 0
  var subsN = 0
  var contents = ""
  var contentsLen = 0
  var lineN = 0
  var fileLines = newSeq[string]()
  var hasSubstitutions = false
  var file: File
  if not file.open(f):
    raise newException(IOError, "Unable to open file '$1'" % f)
  while file.readline(contents):
    lineN.inc
    contentsLen = contents.len
    fileLines.add contents
    var match = matchBounds(contents, options.regex, 0, options)
    var matchstart, matchend: int
    var offset = 0
    while match[0] >= 0:
      matchesN.inc
      matchstart = match[0] 
      matchend = match[1] 
      if options.substitute != "":
        displayFile(f)
        displayMatch(contents, matchstart, matchend, fgRed, lineN)
        var substitute = options.substitute
        var replacement = contents.replace(options.regex, substitute, matchstart, options)
        offset = substitute.len-(matchend-matchstart+1)
        for i in 0..(f.len+1):
          stdout.write(" ")
        displayMatch(replacement, matchstart, matchend+offset, fgGreen, lineN)
        if (options.apply or confirm("Confirm replacement? [y/n] ")):
          hasSubstitutions = true
          subsN.inc
          contents = replacement
          fileLines[fileLines.high] = replacement
      else:
        displayFile(f, silent = options.silent)
        displayMatch(contents, matchstart, matchend, fgGreen, lineN, silent = options.silent)
      match = matchBounds(contents, options.regex, matchend+offset+1, options)
  file.close()
  if (not options.test) and (options.substitute != "") and hasSubstitutions: 
    f.writefile(fileLines.join("\p"))
  return [matchesN, subsN]

## MAIN

## Processing Options

var duration = cpuTime()

var options = FaeOptions(regex: "", insensitive: false, recursive: false, filter: "", substitute: "", directory: ".", apply: false, test: false, silent: false)

for kind, key, val in getOpt():
  case kind:
    of cmdArgument:
      if options.regex == "":
        options.regex = key
      elif options.substitute == "":
        options.substitute = key
      elif options.regex == "" and options.substitute == "":
        quit("Too many arguments", 1)
    of cmdLongOption, cmdShortOption:
      case key:
        of "recursive", "r":
          options.recursive = true
        of "filter", "f":
          options.filter = val
        of "directory", "d":
          options.directory = val
        of "apply", "a":
          options.apply = true
        of "test", "t":
          options.test = true
        of "help", "h":
          echo usage
          quit(0)
        of "version", "v":
          echo version
          quit(0)
        of "insensitive", "i":
          options.insensitive = true
        of "silent", "s":
          options.silent = true
        else:
          discard
    else:
      discard

if options.regex == "":
  echo usage
  quit(0)

## Processing

var count = 0
var matchesN = 0
var subsN = 0
var res: array[0..1, int]

if options.recursive:
  for f in walkDirRec(options.directory):
    if options.filter == "" or f.match(options.filter):
      try:
        count.inc
        res = processFile(f, options)
        matchesN = matchesN + res[0]
        subsN = subsN + res[1]
      except:
        stderr.writeLine getCurrentExceptionMsg()
        continue
else:
  for kind, f in walkDir(options.directory):
    if kind == pcFile and (options.filter == "" or f.match(options.filter)):
      try:
        count.inc
        res = processFile(f, options)
        matchesN = matchesN + res[0]
        subsN = subsN + res[1]
      except:
        echo matchesN, "-------"
        stderr.writeLine getCurrentExceptionMsg()
        continue
if options.substitute != "":
  echo "=== ", count, " files processed - ", matchesN, " matches, ", subsN, " substitutions (", (cpuTime()-duration), " seconds)."
else:
  echo "=== ", count, " files processed - ", matchesN, " matches (", (cpuTime()-duration), " seconds)."
