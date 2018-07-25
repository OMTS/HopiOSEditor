//
//  BinaryOperatorExpr.swift
//  TestLexer
//
//  Created by poisson florent on 05/06/2018.
//  Copyright © 2018 poisson florent. All rights reserved.
//

import Foundation

struct BinaryOperatorExpr: Evaluable {
    
    var binOp: Token
    var lhs: Evaluable
    var rhs: Evaluable

    var description: String {
        return "(" + lhs.description + "\(binOp.rawValue)" + rhs.description + ")"
    }
    
    func evaluate(context: Scope, global: Scope) throws -> Evaluable? {
        switch binOp {
        case .dot:
            return try evaluateDot(context: context, global: global)
        case .plus:
            return try evaluateAddition(context: context, global: global)
        case .minus:
            return try evaluateSubstraction(context: context, global: global)
        case .multiplication:
            return try evaluateMultiplication(context: context, global: global)
        case .divide:
            return try evaluateDivision(context: context, global: global)
        case .remainder:
            return try evaluateRemainder(context: context, global: global)
        case .assignment:
            return try evaluateAssignment(context: context, global: global)
        case .equal:
            return try evaluateEquality(context: context, global: global)
        case .notEqual:
            return try evaluateNonEquality(context: context, global: global)
        case .lessThan:
            return try evaluateLessThanComparison(context: context, global: global)
        case .greaterThan:
            return try evaluateGreaterThanComparison(context: context, global: global)
        case .greaterThanOrEqualTo:
            return try evaluateGreaterThanOrEqualToComparison(context: context, global: global)
        case .lessThanOrEqualTo:
            return try evaluateLessThanOrEqualToComparison(context: context, global: global)
        case .logicalAND:
            return try evaluateLogicalANDComparison(context: context, global: global)
        case .logicalOR:
            return try evaluateLogicalORComparison(context: context, global: global)
        default:
            return nil
        }
    }
    
    private func evaluateDot(context: Scope, global: Scope) throws -> Evaluable? {
//        print("--> evaluateDot: contextId = \(context.uid)")
        let lhsEvaluation = try lhs.evaluate(context: context, global: global)

        // lshEvaluation could be:
            // a module:
                // rshEvaluation could be:
                    // a module <- identifier evaluated as a module
                    // a classe <- identifier evaluated as a class
                    // a variable <- identifier evaluated as a variable
                    // a function call <- function call
        
            // a class:
                // an inner class <- identifier evaluated as a variable
                // a class property <- identifier evaluated as a variable
                // a class method <- function call
        
            // an instance:
                // an instance property <- identifier evaluated as a variable
                // a class property <- identifier evaluated as a variable
                // an instance function call <- function call
                    // lhs is 'super' expression
                        // evaluate with instante.class.superclass
                    // or not
                        // evaluate with instante.class
        
        if let lhsModule = lhsEvaluation as? Module {
            if let rhsIdentifier = rhs as? IdentifierExpr {
                return try rhsIdentifier.evaluate(context: lhsModule.scope, global: global)!

            } else if let rhsFunctionCall = rhs as? FunctionCallExpr {
                // Search for the method in the module
                return try rhsFunctionCall.evaluateFunction(ofModule: lhsModule,
                                                            context: context,
                                                            global: global)
            } else {
                throw InterpreterError.accessorMemberError
            }
        } else if let lhsClasse = lhsEvaluation as? Class {
            if let rhsIdentifier = rhs as? IdentifierExpr {
                // Search class member
                guard let evaluatedRhs = lhsClasse.getClassMember(for: rhsIdentifier.hashId),
                    (evaluatedRhs is Variable || evaluatedRhs is Class) else {
                    throw InterpreterError.unresolvedIdentifier
                }
                return evaluatedRhs

            } else if let rhsFunctionCall = rhs as? FunctionCallExpr {
                return try rhsFunctionCall.evaluateMethod(ofClass: lhsClasse,
                                                          context: context,
                                                          global: global)
            } else {
                throw InterpreterError.accessorMemberError
            }
        } else if let lhsVariable = lhsEvaluation as? Variable,
            let instance = lhsVariable.value as? Instance {
            if let rhsIdentifier = rhs as? IdentifierExpr {
                // Restrain property access if it is accessed from superclass reference
                if lhsVariable.type != instance.class.type {
                    guard let superclass = instance.class.getSuperclass(for: lhsVariable.type.hashId) else {
                        throw InterpreterError.expressionEvaluationError
                    }
                    if !superclass.hasInstanceProperty(with: rhsIdentifier.hashId),
                        superclass.getClassMember(for: rhsIdentifier.hashId) == nil {
                        throw InterpreterError.classMemberNotDeclared
                    }
                }
                
                // Search for property variable in instance symbol table
                if let propertyVariable = instance.scope.getSymbolValue(for: rhsIdentifier.hashId) as? Variable {
                    return propertyVariable
                    
                } else if let propertyVariable = instance.class.getClassMember(for: rhsIdentifier.hashId) as? Variable {
                    // Then search for property variable in class scope
                    // Class properties are shared to all instances
                    return propertyVariable
                    
                } else {
                    throw InterpreterError.accessorMemberError
                }
            } else if let rhsFunctionCall = rhs as? FunctionCallExpr {
                // Restrain method acces if it is accessed from superclass reference
                if lhsVariable.type != instance.class.type {
                    guard let superclass = instance.class.getSuperclass(for: lhsVariable.type.hashId) else {
                        throw InterpreterError.expressionEvaluationError
                    }
                    var methodArgumentNames = [SelfParameter.name]
                    if let argumentNames = rhsFunctionCall.argumentNames {
                        methodArgumentNames.append(contentsOf: argumentNames)
                    }
                    let methodHashId = Closure.getFunctionSignatureHashId(name: rhsFunctionCall.name,
                                                                          argumentNames: methodArgumentNames)
                    if superclass.getClassMember(for: methodHashId) == nil {
                        throw InterpreterError.classMemberNotDeclared
                    }
                }
                
                let inspectedClass = (lhs is SuperExpr ?
                    instance.class.superclass! :
                    instance.class)
                return try rhsFunctionCall.evaluateMethod(ofInstance: instance,
                                                              inspectedClass: inspectedClass,
                                                              context: context,
                                                              global: global)
            } else {
                throw InterpreterError.accessorMemberError
            }
        } else {
            throw InterpreterError.accessorOwnerError
        }
    }
    
    private func evaluateAddition(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
              throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            return Variable(type: .integer, isConstant: true, value: lhsInteger + rhsInteger)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            return Variable(type: .real, isConstant: true, value: lhsReal + rhsReal)
            
        }  else if let lhsString = lhsVariable.value as? String,
            let rhsString = rhsVariable.value as? String {
            return Variable(type: .string, isConstant: true, value: lhsString + rhsString)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateSubstraction(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            return Variable(type: .integer, isConstant: true, value: lhsInteger - rhsInteger)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            return Variable(type: .real, isConstant: true, value: lhsReal - rhsReal)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateMultiplication(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let integerRhs = rhsVariable.value as? Int {
            return Variable(type: .integer, isConstant: true, value: lhsInteger * integerRhs)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            return Variable(type: .real, isConstant: true, value: lhsReal * rhsReal)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateDivision(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            if rhsInteger == 0 {
                throw InterpreterError.zeroDivisionAttempt
            }
            
            return Variable(type: .integer, isConstant: true, value: lhsInteger/rhsInteger)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            if rhsReal == 0 {
                throw InterpreterError.zeroDivisionAttempt
            }
            
            return Variable(type: .real, isConstant: true, value: lhsReal/rhsReal)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateRemainder(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            return Variable(type: .integer, isConstant: true, value: lhsInteger % rhsInteger)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateAssignment(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }
        
        if lhsVariable.isConstant {
            throw InterpreterError.forbiddenAssignment
        }

        if lhsVariable.type != rhsVariable.type {
            throw InterpreterError.binaryOperatorTypeMismatch
        }
        // Check if types match
        if lhsVariable.type != .any {     // `Any` welcome any type
            if lhsVariable.type != rhsVariable.type {
                if let instance = rhsVariable.value as? Instance {
                    if !instance.isInstance(of: lhsVariable.type) {
                        throw InterpreterError.expressionTypeMismatch
                    }
                } else {
                    throw InterpreterError.expressionTypeMismatch
                }
            }
        }
        
        lhsVariable.value = rhsVariable.value

        return nil
    }
    
    private func evaluateEquality(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            return Variable(type: .boolean, isConstant: true, value: lhsInteger == rhsInteger)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            return Variable(type: .boolean, isConstant: true, value: lhsReal == rhsReal)
            
        } else if let lhsString = lhsVariable.value as? String,
            let rhsString = rhsVariable.value as? String {
            return Variable(type: .boolean, isConstant: true, value: lhsString ==  rhsString)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateNonEquality(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            return Variable(type: .boolean, isConstant: true, value: lhsInteger != rhsInteger)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            return Variable(type: .boolean, isConstant: true, value: lhsReal != rhsReal)
            
        } else if let lhsString = lhsVariable.value as? String,
            let rhsString = rhsVariable.value as? String {
            return Variable(type: .boolean, isConstant: true, value: lhsString != rhsString)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateLessThanComparison(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            return Variable(type: .boolean, isConstant: true, value: lhsInteger < rhsInteger)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            return Variable(type: .boolean, isConstant: true, value: lhsReal < rhsReal)
            
        } else if let lhsString = lhsVariable.value as? String,
            let rhsString = rhsVariable.value as? String {
            return Variable(type: .boolean, isConstant: true, value: lhsString < rhsString)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateGreaterThanComparison(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            return Variable(type: .boolean, isConstant: true, value: lhsInteger > rhsInteger)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            return Variable(type: .boolean, isConstant: true, value: lhsReal > rhsReal)
            
        } else if let lhsString = lhsVariable.value as? String,
            let rhsString = rhsVariable.value as? String {
            return Variable(type: .boolean, isConstant: true, value: lhsString > rhsString)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateGreaterThanOrEqualToComparison(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            return Variable(type: .boolean, isConstant: true, value: lhsInteger >= rhsInteger)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            return Variable(type: .boolean, isConstant: true, value: lhsReal >= rhsReal)
            
        } else if let lhsString = lhsVariable.value as? String,
            let rhsString = rhsVariable.value as? String {
            return Variable(type: .boolean, isConstant: true, value: lhsString >= rhsString)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateLessThanOrEqualToComparison(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsInteger = lhsVariable.value as? Int,
            let rhsInteger = rhsVariable.value as? Int {
            return Variable(type: .boolean, isConstant: true, value: lhsInteger <= rhsInteger)
            
        } else if let lhsReal = lhsVariable.value as? Double,
            let rhsReal = rhsVariable.value as? Double {
            return Variable(type: .boolean, isConstant: true, value: lhsReal <= rhsReal)
            
        } else if let lhsString = lhsVariable.value as? String,
            let rhsString = rhsVariable.value as? String {
            return Variable(type: .boolean, isConstant: true, value: lhsString <= rhsString)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateLogicalANDComparison(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsBoolean = lhsVariable.value as? Bool,
            let rhsBoolean = rhsVariable.value as? Bool {
            return Variable(type: .boolean, isConstant: true, value: lhsBoolean && rhsBoolean)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }
    
    private func evaluateLogicalORComparison(context: Scope, global: Scope) throws -> Evaluable? {
        guard let lhsVariable = try lhs.evaluate(context: context, global: global) as? Variable,
            let rhsVariable = try rhs.evaluate(context: context, global: global) as? Variable else {
                throw InterpreterError.expressionEvaluationError
        }

        if let lhsBoolean = lhsVariable.value as? Bool,
            let rhsBoolean = rhsVariable.value as? Bool {
            return Variable(type: .boolean, isConstant: true, value: lhsBoolean || rhsBoolean)
            
        } else {
            throw InterpreterError.expressionEvaluationError
        }
    }

}
