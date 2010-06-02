# Copyright 2010 (C) Dominik Picheta - Read license.txt for the license.
# 31 May 2010

# core - Implements commands like 'print'

proc interpretQuotation*(quot: PType, dataStack: var TStack, vars, gvars: var PType)
proc getModule(name: string, gvars: var PType): seq[PType]
proc loadModules(modules: seq[string], vars, gvars: var PType)

proc invalidTypeErr(got, expected: string): ref ERuntimeError =
  return newException(ERuntimeError, "Error: Invalid types, got $1. Expected $2." % [got, expected])

proc command*(cmnd: string, dataStack: var TStack, vars, gvars: var PType) =
  case cmnd
  of "print":
    var first = dataStack.pop()
    echo(toString(first))
  of "call":
    var first = dataStack.pop()
    interpretQuotation(first, dataStack, vars, gvars)
  of "import":
    var first = dataStack.pop()
    if first.kind == ntString:
      loadModules(@[first.value], vars, gvars)
  of "+", "-", "*", "/":
    var first = datastack.pop()
    var second = datastack.pop()
  
    if cmnd == "+":
      if first.kind == ntInt and second.kind == ntInt:
        dataStack.push(newInt(second.iValue + first.iValue))
      elif first.kind == ntString and second.kind == ntString:
        dataStack.push(newString(second.value & first.value))
      else:
        raise invalidTypeErr($first.kind & " and " & $second.kind, "string, string or int, int")
        
    elif cmnd == "-":
      if first.kind == ntInt and second.kind == ntInt:
        dataStack.push(newInt(second.iValue - first.iValue))
      else:
        raise invalidTypeErr($first.kind & " and " & $second.kind, "int, int")
        
    elif cmnd == "*":
      if first.kind == ntInt and second.kind == ntInt:
        dataStack.push(newInt(second.iValue * first.iValue))
      else:
        raise invalidTypeErr($first.kind & " and " & $second.kind, "int, int")
                        
    elif cmnd == "/":
      if first.kind == ntInt and second.kind == ntInt:
        dataStack.push(newInt(second.iValue div first.iValue))
      else:
        raise invalidTypeErr($first.kind & " and " & $second.kind, "int, int")
  
  of "!":
    # Negate a boolean
    var first = dataStack.pop()
    if first.kind == ntBool:
      dataStack.push(newBool(not first.bValue))
    else:
      raise invalidTypeErr($first.kind, "bool")
  
  of "if":
    # Depending on a boolean on the stack, executes a particular quotation
    # (cond) (then) (else) if
    var theElse = datastack.pop()
    var then = datastack.pop()
    var cond = datastack.pop()
    
    if cond.kind == ntQuot and theElse.kind == ntQuot and then.kind == ntQuot:
      interpretQuotation(cond, dataStack, vars, gvars)
      var boolean = dataStack.pop()
      if boolean.kind != ntBool:
        raise invalidTypeErr($boolean.kind, "bool")
      
      if boolean.bValue:
        interpretQuotation(then, dataStack, vars, gvars)
      else:
        interpretQuotation(theElse, dataStack, vars, gvars)
    else:
      raise invalidTypeErr($cond.kind & ", " & $theElse.kind & " and " & $then.kind,
              "quot, quot, quot")
  of "while":
    # Loop until cond becomes false
    # (cond) (do) while
    var do = dataStack.pop()
    var cond = dataStack.pop()
    
    if do.kind == ntQuot and cond.kind == ntQuot:
      interpretQuotation(cond, dataStack, vars, gvars)
      var boolean = dataStack.pop()
      if boolean.kind != ntBool:
        raise invalidTypeErr($boolean.kind, "bool")
  
      while boolean.bValue:
        interpretQuotation(cond, dataStack, vars, gvars)
        boolean = dataStack.pop()
        
        interpretQuotation(do, dataStack, vars, gvars)
  
  else:
    var tVar: PType
    if not ("." in cmnd):
      tVar = vars.getVar(cmnd)
      if tVar == nil:
        tVar = gvars.getVar(cmnd)
    else:
      # cmnd contains a dot
      var before = cmnd.split('.')[0]
      var after = cmnd.split('.')[1]
      
      var module = getModule(before, gvars) # [name, {locals}, {globals}]
      if module == nil: tVar = nil
      else:
        tVar = module[2].getVar(after)
    
    if tVar == nil:
      raise newException(ERuntimeError, "Error: $1 is not declared." % [cmnd])
    
    if tVar.kind != ntFunc:
      dataStack.push(tVar)
    else:
      # Function call
      var localVars = newVariables() # This functions local variables
      var funcStack = newStack(200) # This functions stack
      
      # Add the arguments in reverse, so that the 'nael rule' applies
      # 5 6 foo -> foo(5,6)
      for i in countdown(tVar.args.len()-1, 0):
        var arg = tVar.args[i]
        if arg.kind == ntCmnd:
          try:
            var first = dataStack.pop()
          
            localVars.declVar(arg.value)
            localVars.setVar(arg.value, first)
          except EOverflow:
            # TODO: Check if this works, After araq fixes the exception bug
            raise newException(ERuntimeError, 
                    "Error: $1 expects $2 args, got $3" %
                            [cmnd, $(tVar.args.len()-1), $(i)])

        else:
          raise newException(ERuntimeError, "Error: " & cmnd &
                  " contains unexpected args, of kind " & $arg.kind)
      
      interpretQuotation(tVar.quot, funcStack, localVars, gvars)

proc interpretQuotation*(quot: PType, dataStack: var TStack, vars, gvars: var PType) =
  if quot.kind != ntQuot:
    raise newException(EInvalidValue, "Error: Argument given is not a quotation")
  
  for item in items(quot.lvalue):
    case item.kind
    of ntInt, ntFloat, ntString, ntBool, ntList, ntQuot, ntDict, ntNil, ntFunc:
      dataStack.push(item)
    of ntCmnd:
      command(item.value, dataStack, vars, gvars)
    of ntAstNode:
      case item.node.kind:
      of nnkVarDeclar:
        vars.declVar(item.node.value)
      of nnkVarSet:
        vars.setVar(item.node.name, toPType(item.node.setValue))
      of nnkFunc:
        gvars.declVar(item.node.fName)
        gvars.setVar(item.node.fName, newFunc(item.node))
      else:
        raise newException(ERuntimeError, "Error: Unexpected AstNode in quotation, " & $item.node.kind)

proc getModule(name: string, gvars: var PType): seq[PType] =
  var modulesVar = gvars.getVar("__modules__")
  for module in items(modulesVar.lValue):
    if module.kind == ntList:
      if module.lValue[0].kind == ntString:
        if module.lValue[0].value == name:
          return module.lValue
      else:
        raise newException(ERuntimeError, "Error: Invalid type, expected ntString got " & $module.lValue[0].kind)
      
  return nil

proc loadModules(modules: seq[string], vars, gvars: var PType) =
  var paths = gvars.getVar("__path__")
  var modulesVar = gvars.getVar("__modules__")
  if paths != nil and modulesVar != nil:
    for module in items(modules):
      # Check if the module exists
      if getModule(module, gvars) != nil:
        raise newException(ERuntimeError, "Error: Unable to load " &
                module & ", module is already loaded.")
    
      for path in items(paths.lValue):
        if path.kind == ntString:
          var file = readFile(path.value / module & ".nael")
          if file != nil:
            var locals = newVariables()
            var globals = newVariables()
            globals.addStandard()
            var moduleStack = newStack(200)
            
            var ast = parse(file)
            interpret(ast, moduleStack, locals, globals)
            
            var moduleList = newList(@[newString(module), locals, globals]) # [name, {locals}, {globals}]
            modulesVar.lValue.add(moduleList)
          else:
            raise newException(ERuntimeError, "Error: Unable to load " &
                    module & ", module cannot be found.")
        else:
          raise newException(ERuntimeError, "Error: Unable to load " &
                  module & ", incorrect path, got type " & $path.kind)

  else:
    raise newException(ERuntimeError, "Error: Unable to load module, path and/or modules variable is not declared.")


