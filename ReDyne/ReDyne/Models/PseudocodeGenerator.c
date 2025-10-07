#include "PseudocodeGenerator.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// MARK: - Memory Management

PseudocodeContext* pseudocode_create_context(void) {
    PseudocodeContext *ctx = calloc(1, sizeof(PseudocodeContext));
    if (!ctx) return NULL;
    
    ctx->generateComments = true;
    ctx->simplifyExpressions = true;
    ctx->reconstructLoops = true;
    ctx->useTypeCasting = true;
    ctx->indentSize = 4;
    
    return ctx;
}

void pseudocode_free_context(PseudocodeContext *ctx) {
    if (!ctx) return;
    
    for (int i = 0; i < ctx->functionCount; i++) {
        pseudocode_free_function(ctx->functions[i]);
    }
    free(ctx->functions);
    
    for (int i = 0; i < ctx->typeCacheSize; i++) {
        free(ctx->typeCache[i]);
    }
    free(ctx->typeCache);
    
    for (int i = 0; i < ctx->symbolCount; i++) {
        free(ctx->symbolNames[i]);
    }
    free(ctx->symbolNames);
    free(ctx->symbolAddresses);
    
    free(ctx);
}

void pseudocode_free_expression(Expression *expr) {
    if (!expr) return;
    
    switch (expr->type) {
        case EXPR_BINARY_OP:
            pseudocode_free_expression(expr->binaryOp.left);
            pseudocode_free_expression(expr->binaryOp.right);
            break;
        case EXPR_UNARY_OP:
            pseudocode_free_expression(expr->unaryOp.operand);
            break;
        case EXPR_MEMORY_ACCESS:
            pseudocode_free_expression(expr->memAccess.base);
            pseudocode_free_expression(expr->memAccess.offset);
            break;
        case EXPR_FUNCTION_CALL:
            for (int i = 0; i < expr->call.argCount; i++) {
                pseudocode_free_expression(expr->call.args[i]);
            }
            free(expr->call.args);
            break;
        case EXPR_CAST:
            pseudocode_free_expression(expr->cast.expr);
            free(expr->cast.targetType);
            break;
        case EXPR_TERNARY:
            pseudocode_free_expression(expr->ternary.condition);
            pseudocode_free_expression(expr->ternary.trueExpr);
            pseudocode_free_expression(expr->ternary.falseExpr);
            break;
        default:
            break;
    }
    
    free(expr->dataType);
    free(expr);
}

void pseudocode_free_statement(Statement *stmt) {
    if (!stmt) return;
    
    switch (stmt->type) {
        case STMT_ASSIGNMENT:
            pseudocode_free_expression(stmt->assignment.value);
            break;
        case STMT_IF:
            pseudocode_free_expression(stmt->ifStmt.condition);
            for (int i = 0; i < stmt->ifStmt.thenCount; i++) {
                pseudocode_free_statement(stmt->ifStmt.thenBlock[i]);
            }
            free(stmt->ifStmt.thenBlock);
            for (int i = 0; i < stmt->ifStmt.elseCount; i++) {
                pseudocode_free_statement(stmt->ifStmt.elseBlock[i]);
            }
            free(stmt->ifStmt.elseBlock);
            break;
        case STMT_WHILE:
        case STMT_DO_WHILE:
            pseudocode_free_expression(stmt->whileStmt.condition);
            for (int i = 0; i < stmt->whileStmt.bodyCount; i++) {
                pseudocode_free_statement(stmt->whileStmt.body[i]);
            }
            free(stmt->whileStmt.body);
            break;
        case STMT_RETURN:
            pseudocode_free_expression(stmt->returnStmt.value);
            break;
        case STMT_CALL:
            pseudocode_free_expression(stmt->callStmt.call);
            break;
        default:
            break;
    }
    
    free(stmt);
}

void pseudocode_free_function(PseudoFunction *func) {
    if (!func) return;
    
    for (int i = 0; i < func->paramCount; i++) {
        free(func->paramNames[i]);
        free(func->paramTypes[i]);
    }
    free(func->paramNames);
    free(func->paramTypes);
    
    for (int i = 0; i < func->localCount; i++) {
        free(func->localNames[i]);
        free(func->localTypes[i]);
    }
    free(func->localNames);
    free(func->localTypes);
    free(func->returnType);
    
    for (int i = 0; i < func->statementCount; i++) {
        pseudocode_free_statement(func->statements[i]);
    }
    free(func->statements);
    
    free(func);
}

// MARK: - Expression Building

static Expression* create_constant_expr(uint64_t value) {
    Expression *expr = calloc(1, sizeof(Expression));
    expr->type = EXPR_CONSTANT;
    expr->constant.value = value;
    expr->constant.isFloat = false;
    return expr;
}

static Expression* create_variable_expr(const char *name) {
    Expression *expr = calloc(1, sizeof(Expression));
    expr->type = EXPR_VARIABLE;
    snprintf(expr->variable.name, sizeof(expr->variable.name), "%s", name);
    expr->variable.version = 0;
    return expr;
}

static Expression* create_binary_expr(Operator op, Expression *left, Expression *right) {
    Expression *expr = calloc(1, sizeof(Expression));
    expr->type = EXPR_BINARY_OP;
    expr->binaryOp.op = op;
    expr->binaryOp.left = left;
    expr->binaryOp.right = right;
    return expr;
}

Expression* pseudocode_build_expression(PseudocodeContext *ctx, const PseudocodeInstruction *inst) {
    if (!ctx || !inst) return NULL;
    
    const char *mnemonic = inst->mnemonic;
    
    if (strncmp(mnemonic, "add", 3) == 0 || strncmp(mnemonic, "ADD", 3) == 0) {
        char dest[32], src1[32], src2[32];
        if (sscanf(inst->operands, "%[^,], %[^,], %s", dest, src1, src2) == 3) {
            Expression *left = create_variable_expr(src1);
            Expression *right;
            
            if (src2[0] == '#') {
                uint64_t imm = strtoull(src2 + 1, NULL, 0);
                right = create_constant_expr(imm);
            } else {
                right = create_variable_expr(src2);
            }
            
            return create_binary_expr(OP_ADD, left, right);
        }
    }
    
    if (strncmp(mnemonic, "sub", 3) == 0 || strncmp(mnemonic, "SUB", 3) == 0) {
        char dest[32], src1[32], src2[32];
        if (sscanf(inst->operands, "%[^,], %[^,], %s", dest, src1, src2) == 3) {
            Expression *left = create_variable_expr(src1);
            Expression *right;
            
            if (src2[0] == '#') {
                uint64_t imm = strtoull(src2 + 1, NULL, 0);
                right = create_constant_expr(imm);
            } else {
                right = create_variable_expr(src2);
            }
            
            return create_binary_expr(OP_SUB, left, right);
        }
    }
    
    if (strncmp(mnemonic, "mov", 3) == 0 || strncmp(mnemonic, "MOV", 3) == 0) {
        char dest[32], src[32];
        if (sscanf(inst->operands, "%[^,], %s", dest, src) == 2) {
            if (src[0] == '#') {
                uint64_t imm = strtoull(src + 1, NULL, 0);
                return create_constant_expr(imm);
            } else {
                return create_variable_expr(src);
            }
        }
    }
    
    if (strncmp(mnemonic, "ldr", 3) == 0 || strncmp(mnemonic, "LDR", 3) == 0) {
        Expression *memExpr = calloc(1, sizeof(Expression));
        memExpr->type = EXPR_MEMORY_ACCESS;
        memExpr->memAccess.size = (mnemonic[3] == 'b' || mnemonic[3] == 'B') ? 1 : 
                                  (mnemonic[3] == 'h' || mnemonic[3] == 'H') ? 2 :
                                  (mnemonic[3] == 'w' || mnemonic[3] == 'W') ? 4 : 8;
        
        char dest[32], base[32];
        int offset;
        if (sscanf(inst->operands, "%[^,], [%[^,], #%d]", dest, base, &offset) == 3) {
            memExpr->memAccess.base = create_variable_expr(base);
            memExpr->memAccess.offset = create_constant_expr(offset);
        } else if (sscanf(inst->operands, "%[^,], [%[^]]", dest, base) == 2) {
            memExpr->memAccess.base = create_variable_expr(base);
            memExpr->memAccess.offset = NULL;
        }
        
        return memExpr;
    }
    
    if (strncmp(mnemonic, "str", 3) == 0 || strncmp(mnemonic, "STR", 3) == 0) {
        Expression *memExpr = calloc(1, sizeof(Expression));
        memExpr->type = EXPR_MEMORY_ACCESS;
        memExpr->memAccess.size = (mnemonic[3] == 'b' || mnemonic[3] == 'B') ? 1 : 
                                  (mnemonic[3] == 'h' || mnemonic[3] == 'H') ? 2 :
                                  (mnemonic[3] == 'w' || mnemonic[3] == 'W') ? 4 : 8;
        
        char src[32], base[32];
        int offset;
        if (sscanf(inst->operands, "%[^,], [%[^,], #%d]", src, base, &offset) == 3) {
            memExpr->memAccess.base = create_variable_expr(base);
            memExpr->memAccess.offset = create_constant_expr(offset);
        } else if (sscanf(inst->operands, "%[^,], [%[^]]", src, base) == 2) {
            memExpr->memAccess.base = create_variable_expr(base);
            memExpr->memAccess.offset = NULL;
        }
        
        return memExpr;
    }
    
    if (strncmp(mnemonic, "mul", 3) == 0 || strncmp(mnemonic, "MUL", 3) == 0) {
        char dest[32], src1[32], src2[32];
        if (sscanf(inst->operands, "%[^,], %[^,], %s", dest, src1, src2) == 3) {
            Expression *left = create_variable_expr(src1);
            Expression *right = create_variable_expr(src2);
            return create_binary_expr(OP_MUL, left, right);
        }
    }
    
    if (strncmp(mnemonic, "and", 3) == 0 || strncmp(mnemonic, "AND", 3) == 0) {
        char dest[32], src1[32], src2[32];
        if (sscanf(inst->operands, "%[^,], %[^,], %s", dest, src1, src2) == 3) {
            Expression *left = create_variable_expr(src1);
            Expression *right;
            if (src2[0] == '#') {
                right = create_constant_expr(strtoull(src2 + 1, NULL, 0));
            } else {
                right = create_variable_expr(src2);
            }
            return create_binary_expr(OP_AND, left, right);
        }
    }
    
    if (strncmp(mnemonic, "orr", 3) == 0 || strncmp(mnemonic, "ORR", 3) == 0) {
        char dest[32], src1[32], src2[32];
        if (sscanf(inst->operands, "%[^,], %[^,], %s", dest, src1, src2) == 3) {
            Expression *left = create_variable_expr(src1);
            Expression *right;
            if (src2[0] == '#') {
                right = create_constant_expr(strtoull(src2 + 1, NULL, 0));
            } else {
                right = create_variable_expr(src2);
            }
            return create_binary_expr(OP_OR, left, right);
        }
    }
    
    if (strncmp(mnemonic, "eor", 3) == 0 || strncmp(mnemonic, "EOR", 3) == 0) {
        char dest[32], src1[32], src2[32];
        if (sscanf(inst->operands, "%[^,], %[^,], %s", dest, src1, src2) == 3) {
            Expression *left = create_variable_expr(src1);
            Expression *right;
            if (src2[0] == '#') {
                right = create_constant_expr(strtoull(src2 + 1, NULL, 0));
            } else {
                right = create_variable_expr(src2);
            }
            return create_binary_expr(OP_XOR, left, right);
        }
    }
    
    if (strncmp(mnemonic, "bl", 2) == 0 || strncmp(mnemonic, "BL", 2) == 0) {
        Expression *callExpr = calloc(1, sizeof(Expression));
        callExpr->type = EXPR_FUNCTION_CALL;
        
        char funcName[128];
        if (sscanf(inst->operands, "%s", funcName) == 1) {
            const char *name = funcName[0] == '_' ? funcName + 1 : funcName;
            snprintf(callExpr->call.name, sizeof(callExpr->call.name), "%s", name);
        } else {
            snprintf(callExpr->call.name, sizeof(callExpr->call.name), "FUN_%08llx", 
                    (unsigned long long)inst->address);
        }
        
        callExpr->call.argCount = 0;
        callExpr->call.args = NULL;
        return callExpr;
    }
    
    Expression *callExpr = calloc(1, sizeof(Expression));
    callExpr->type = EXPR_FUNCTION_CALL;
    snprintf(callExpr->call.name, sizeof(callExpr->call.name), "__%s", mnemonic);
    callExpr->call.argCount = 0;
    callExpr->call.args = NULL;
    
    return callExpr;
}

// MARK: - Type Inference

PseudoTypeInfo* pseudocode_infer_type(PseudocodeContext *ctx, const Expression *expr) {
    if (!expr) return NULL;
    
    PseudoTypeInfo *type = calloc(1, sizeof(PseudoTypeInfo));
    
    switch (expr->type) {
        case EXPR_CONSTANT:
            if (expr->constant.value <= 0xFF) {
                type->type = TYPE_UINT8;
                type->size = 1;
                strcpy(type->name, "uint8_t");
            } else if (expr->constant.value <= 0xFFFF) {
                type->type = TYPE_UINT16;
                type->size = 2;
                strcpy(type->name, "uint16_t");
            } else if (expr->constant.value <= 0xFFFFFFFF) {
                type->type = TYPE_UINT32;
                type->size = 4;
                strcpy(type->name, "uint32_t");
            } else {
                type->type = TYPE_UINT64;
                type->size = 8;
                strcpy(type->name, "uint64_t");
            }
            break;
            
        case EXPR_VARIABLE:
            type->type = TYPE_UINT64;
            type->size = 8;
            strcpy(type->name, "uint64_t");
            break;
            
        case EXPR_MEMORY_ACCESS:
            type->type = TYPE_POINTER;
            type->pointerLevel = 1;
            type->size = 8;
            strcpy(type->name, "void*");
            break;
            
        case EXPR_BINARY_OP:
            {
                PseudoTypeInfo *leftType = pseudocode_infer_type(ctx, expr->binaryOp.left);
                PseudoTypeInfo *rightType = pseudocode_infer_type(ctx, expr->binaryOp.right);
                
                if (leftType && rightType) {
                    if (leftType->size >= rightType->size) {
                        memcpy(type, leftType, sizeof(PseudoTypeInfo));
                    } else {
                        memcpy(type, rightType, sizeof(PseudoTypeInfo));
                    }
                }
                
                free(leftType);
                free(rightType);
            }
            break;
            
        default:
            type->type = TYPE_UNKNOWN;
            strcpy(type->name, "unknown");
            break;
    }
    
    return type;
}

// MARK: - Code Generation

static const char* operator_to_string(Operator op) {
    switch (op) {
        case OP_ADD: return "+";
        case OP_SUB: return "-";
        case OP_MUL: return "*";
        case OP_DIV: return "/";
        case OP_MOD: return "%";
        case OP_SHL: return "<<";
        case OP_SHR: return ">>";
        case OP_AND: return "&";
        case OP_OR: return "|";
        case OP_XOR: return "^";
        case OP_EQ: return "==";
        case OP_NE: return "!=";
        case OP_LT: return "<";
        case OP_LE: return "<=";
        case OP_GT: return ">";
        case OP_GE: return ">=";
        case OP_LAND: return "&&";
        case OP_LOR: return "||";
        case OP_NEG: return "-";
        case OP_NOT: return "~";
        case OP_LNOT: return "!";
        default: return "?";
    }
}

char* pseudocode_format_expression(const Expression *expr) {
    if (!expr) return strdup("null");
    
    char *result = malloc(1024);
    result[0] = '\0';
    
    switch (expr->type) {
        case EXPR_CONSTANT:
            if (expr->constant.isFloat) {
                snprintf(result, 1024, "%.2f", expr->constant.floatValue);
            } else {
                snprintf(result, 1024, "0x%llx", expr->constant.value);
            }
            break;
            
        case EXPR_VARIABLE:
            snprintf(result, 1024, "%s", expr->variable.name);
            break;
            
        case EXPR_BINARY_OP: {
            char *left = pseudocode_format_expression(expr->binaryOp.left);
            char *right = pseudocode_format_expression(expr->binaryOp.right);
            snprintf(result, 1024, "(%s %s %s)", 
                    left, operator_to_string(expr->binaryOp.op), right);
            free(left);
            free(right);
            break;
        }
            
        case EXPR_UNARY_OP: {
            char *operand = pseudocode_format_expression(expr->unaryOp.operand);
            snprintf(result, 1024, "%s%s", 
                    operator_to_string(expr->unaryOp.op), operand);
            free(operand);
            break;
        }
            
        case EXPR_MEMORY_ACCESS: {
            char *base = pseudocode_format_expression(expr->memAccess.base);
            if (expr->memAccess.offset) {
                char *offset = pseudocode_format_expression(expr->memAccess.offset);
                snprintf(result, 1024, "*(%s + %s)", base, offset);
                free(offset);
            } else {
                snprintf(result, 1024, "*%s", base);
            }
            free(base);
            break;
        }
            
        case EXPR_FUNCTION_CALL:
            snprintf(result, 1024, "%s(...)", expr->call.name);
            break;
            
        default:
            snprintf(result, 1024, "<expr>");
            break;
    }
    
    return result;
}

char* pseudocode_format_type(const PseudoTypeInfo *type) {
    if (!type) return strdup("void");
    
    char *result = malloc(256);
    strcpy(result, type->name);
    
    for (int i = 0; i < type->pointerLevel; i++) {
        strcat(result, "*");
    }
    
    return result;
}

// MARK: - Simple Statement Generation

Statement** pseudocode_reconstruct_control_flow(
    PseudocodeContext *ctx,
    const PseudocodeInstruction *instructions,
    int count,
    int *outStatementCount
) {
    if (!ctx || !instructions || count <= 0) {
        *outStatementCount = 0;
        return NULL;
    }
    
    Statement **statements = calloc(count, sizeof(Statement*));
    int stmtCount = 0;
    
    for (int i = 0; i < count; i++) {
        const PseudocodeInstruction *inst = &instructions[i];
        Statement *stmt = NULL;
        
        if (strcmp(inst->mnemonic, "ret") == 0 || strcmp(inst->mnemonic, "RET") == 0) {
            stmt = calloc(1, sizeof(Statement));
            stmt->type = STMT_RETURN;
            stmt->address = inst->address;
            stmt->returnStmt.value = create_variable_expr("x0");
        }

        else if (strncmp(inst->mnemonic, "b", 1) == 0 && strcmp(inst->mnemonic, "bl") != 0 && strcmp(inst->mnemonic, "blr") != 0) {
            stmt = calloc(1, sizeof(Statement));
            
            if (strchr(inst->mnemonic, '.') != NULL || 
                strncmp(inst->mnemonic, "cb", 2) == 0 ||
                strncmp(inst->mnemonic, "tb", 2) == 0) {
                
                stmt->type = STMT_IF;
                stmt->address = inst->address;
                
                Expression *cond = calloc(1, sizeof(Expression));
                cond->type = EXPR_VARIABLE;
                
                if (strstr(inst->mnemonic, ".eq")) {
                    strcpy(cond->variable.name, "(flags == 0)");
                } else if (strstr(inst->mnemonic, ".ne")) {
                    strcpy(cond->variable.name, "(flags != 0)");
                } else if (strstr(inst->mnemonic, ".lt")) {
                    strcpy(cond->variable.name, "(signed_less)");
                } else if (strstr(inst->mnemonic, ".gt")) {
                    strcpy(cond->variable.name, "(signed_greater)");
                } else if (strncmp(inst->mnemonic, "cbz", 3) == 0) {
                    char reg[32];
                    if (sscanf(inst->operands, "%[^,]", reg) == 1) {
                        snprintf(cond->variable.name, sizeof(cond->variable.name), "(%s == 0)", reg);
                    } else {
                        strcpy(cond->variable.name, "(reg == 0)");
                    }
                } else if (strncmp(inst->mnemonic, "cbnz", 4) == 0) {
                    char reg[32];
                    if (sscanf(inst->operands, "%[^,]", reg) == 1) {
                        snprintf(cond->variable.name, sizeof(cond->variable.name), "(%s != 0)", reg);
                    } else {
                        strcpy(cond->variable.name, "(reg != 0)");
                    }
                } else {
                    strcpy(cond->variable.name, "condition");
                }
                
                stmt->ifStmt.condition = cond;
                stmt->ifStmt.thenBlock = NULL;
                stmt->ifStmt.thenCount = 0;
                stmt->ifStmt.elseBlock = NULL;
                stmt->ifStmt.elseCount = 0;
            } else {
                stmt->type = STMT_GOTO;
                stmt->address = inst->address;
            }
            
            char target[32];
            uint64_t targetAddr = 0;
            if (sscanf(inst->operands, "#%s", target) == 1 ||
                sscanf(inst->operands, "%*[^,], #%s", target) == 1 ||
                sscanf(inst->operands, "%*[^,], %*[^,], #%s", target) == 1) {
                if (target[0] == '0' && (target[1] == 'x' || target[1] == 'X')) {
                    targetAddr = strtoull(target, NULL, 16);
                } else {
                    int64_t offset = strtoll(target, NULL, 0);
                    targetAddr = inst->address + (uint64_t)offset;
                }
            }
            
            if (targetAddr != 0) {
                snprintf(stmt->gotoLabel.label, sizeof(stmt->gotoLabel.label), 
                        "LAB_%08llx", (unsigned long long)targetAddr);
            } else {
                snprintf(stmt->gotoLabel.label, sizeof(stmt->gotoLabel.label), 
                        "LAB_%08llx", (unsigned long long)(inst->address + 4));
            }
        }
        
        else {
            Expression *expr = pseudocode_build_expression(ctx, inst);
            if (expr) {
                stmt = calloc(1, sizeof(Statement));
                stmt->type = STMT_ASSIGNMENT;
                stmt->address = inst->address;
                
                char dest[32];
                if (sscanf(inst->operands, "%[^,]", dest) == 1) {
                    char *p = dest;
                    while (*p && isspace(*p)) p++;
                    char *end = p + strlen(p) - 1;
                    while (end > p && isspace(*end)) *end-- = '\0';
                    
                    snprintf(stmt->assignment.varName, sizeof(stmt->assignment.varName), "%s", p);
                    stmt->assignment.value = expr;
                } else {
                    free(stmt);
                    stmt = calloc(1, sizeof(Statement));
                    stmt->type = STMT_CALL;
                    stmt->address = inst->address;
                    stmt->callStmt.call = expr;
                }
            }
        }
        
        if (stmt) {
            stmt->lineNumber = stmtCount + 1;
            statements[stmtCount++] = stmt;
        }
    }
    
    *outStatementCount = stmtCount;
    return statements;
}

// MARK: - C-like Code Generation

static void append_indented(char **output, int indent, const char *line) {
    char *old = *output;
    int oldLen = old ? strlen(old) : 0;
    int newLen = oldLen + indent + strlen(line) + 2;
    
    *output = realloc(old, newLen);
    
    char *p = *output + oldLen;
    for (int i = 0; i < indent; i++) {
        *p++ = ' ';
    }
    strcpy(p, line);
    strcat(p, "\n");
}

char* pseudocode_generate_c_like(PseudocodeContext *ctx, const PseudoFunction *function) {
    if (!ctx || !function) return NULL;
    
    char *output = calloc(1, 1);
    char line[1024];
    char *retType = pseudocode_format_type(function->returnType);
    snprintf(line, sizeof(line), "%s %s(", retType, function->name);
    free(retType);
    
    for (int i = 0; i < function->paramCount; i++) {
        char *paramType = pseudocode_format_type(function->paramTypes[i]);
        char param[128];
        snprintf(param, sizeof(param), "%s %s", paramType, function->paramNames[i]);
        strcat(line, param);
        if (i < function->paramCount - 1) strcat(line, ", ");
        free(paramType);
    }
    strcat(line, ") {");
    append_indented(&output, 0, line);
    
    if (function->localCount > 0) {
        append_indented(&output, ctx->indentSize, "// Local variables");
        for (int i = 0; i < function->localCount; i++) {
            char *localType = pseudocode_format_type(function->localTypes[i]);
            snprintf(line, sizeof(line), "%s %s;", localType, function->localNames[i]);
            append_indented(&output, ctx->indentSize, line);
            free(localType);
        }
        append_indented(&output, 0, "");
    }
    
    for (int i = 0; i < function->statementCount; i++) {
        Statement *stmt = function->statements[i];
        
        switch (stmt->type) {
            case STMT_ASSIGNMENT: {
                char *exprStr = pseudocode_format_expression(stmt->assignment.value);
                snprintf(line, sizeof(line), "%s = %s;", stmt->assignment.varName, exprStr);
                append_indented(&output, ctx->indentSize, line);
                free(exprStr);
                break;
            }
            
            case STMT_RETURN: {
                if (stmt->returnStmt.value) {
                    char *exprStr = pseudocode_format_expression(stmt->returnStmt.value);
                    snprintf(line, sizeof(line), "return %s;", exprStr);
                    free(exprStr);
                } else {
                    snprintf(line, sizeof(line), "return;");
                }
                append_indented(&output, ctx->indentSize, line);
                break;
            }
            
            case STMT_GOTO:
                snprintf(line, sizeof(line), "goto %s;", stmt->gotoLabel.label);
                append_indented(&output, ctx->indentSize, line);
                break;
            
            case STMT_LABEL:
                snprintf(line, sizeof(line), "%s:", stmt->gotoLabel.label);
                append_indented(&output, 0, line);
                break;
            
            default:
                snprintf(line, sizeof(line), "// Statement type %d", stmt->type);
                append_indented(&output, ctx->indentSize, line);
                break;
        }
    }
    
    append_indented(&output, 0, "}");
    
    return output;
}

char* pseudocode_generate_python_like(PseudocodeContext *ctx, const PseudoFunction *function) {
    if (!ctx || !function) return NULL;
    
    char *output = calloc(1, 1);
    char line[1024];
    
    snprintf(line, sizeof(line), "def %s(", function->name);
    
    for (int i = 0; i < function->paramCount; i++) {
        strcat(line, function->paramNames[i]);
        if (i < function->paramCount - 1) strcat(line, ", ");
    }
    strcat(line, "):");
    append_indented(&output, 0, line);
    
    for (int i = 0; i < function->statementCount; i++) {
        Statement *stmt = function->statements[i];
        
        switch (stmt->type) {
            case STMT_ASSIGNMENT: {
                char *exprStr = pseudocode_format_expression(stmt->assignment.value);
                snprintf(line, sizeof(line), "%s = %s", stmt->assignment.varName, exprStr);
                append_indented(&output, ctx->indentSize, line);
                free(exprStr);
                break;
            }
            
            case STMT_RETURN: {
                if (stmt->returnStmt.value) {
                    char *exprStr = pseudocode_format_expression(stmt->returnStmt.value);
                    snprintf(line, sizeof(line), "return %s", exprStr);
                    free(exprStr);
                } else {
                    snprintf(line, sizeof(line), "return");
                }
                append_indented(&output, ctx->indentSize, line);
                break;
            }
            
            default:
                snprintf(line, sizeof(line), "# Statement type %d", stmt->type);
                append_indented(&output, ctx->indentSize, line);
                break;
        }
    }
    
    return output;
}

// MARK: - Function Generation

PseudoFunction* pseudocode_generate_function(
    PseudocodeContext *ctx,
    const PseudocodeInstruction *instructions,
    int count,
    uint64_t startAddress
) {
    if (!ctx || !instructions || count <= 0) return NULL;
    
    PseudoFunction *func = calloc(1, sizeof(PseudoFunction));
    
    snprintf(func->name, sizeof(func->name), "FUN_%08llx", (unsigned long long)startAddress);
    func->address = startAddress;
    
    if (count > 0) {
        func->size = instructions[count - 1].address - startAddress + 4;
    }
    
    func->returnType = calloc(1, sizeof(PseudoTypeInfo));
    func->returnType->type = TYPE_UINT64;
    func->returnType->size = 8;
    strcpy(func->returnType->name, "uint64_t");
    
    func->paramCount = 4;
    func->paramNames = calloc(func->paramCount, sizeof(char*));
    func->paramTypes = calloc(func->paramCount, sizeof(PseudoTypeInfo*));
    
    for (int i = 0; i < func->paramCount; i++) {
        func->paramNames[i] = malloc(32);
        snprintf(func->paramNames[i], 32, "arg%d", i);
        
        func->paramTypes[i] = calloc(1, sizeof(PseudoTypeInfo));
        func->paramTypes[i]->type = TYPE_UINT64;
        func->paramTypes[i]->size = 8;
        strcpy(func->paramTypes[i]->name, "uint64_t");
    }
    
    func->statements = pseudocode_reconstruct_control_flow(
        ctx, instructions, count, &func->statementCount
    );
    
    return func;
}

// MARK: - Expression Formatting Helpers

static int format_expression_inline(const Expression *expr, char *buffer) {
    if (!expr || !buffer) return 0;
    
    char *start = buffer;
    
    switch (expr->type) {
        case EXPR_CONSTANT:
            buffer += sprintf(buffer, "0x%llx", (unsigned long long)expr->constant.value);
            break;
            
        case EXPR_VARIABLE:
            buffer += sprintf(buffer, "%s", expr->variable.name);
            break;
            
        case EXPR_BINARY_OP: {
            const char *op_str = "";
            switch (expr->binaryOp.op) {
                case OP_ADD: op_str = " + "; break;
                case OP_SUB: op_str = " - "; break;
                case OP_MUL: op_str = " * "; break;
                case OP_DIV: op_str = " / "; break;
                case OP_MOD: op_str = " % "; break;
                case OP_SHL: op_str = " << "; break;
                case OP_SHR: op_str = " >> "; break;
                case OP_AND: op_str = " & "; break;
                case OP_OR: op_str = " | "; break;
                case OP_XOR: op_str = " ^ "; break;
                case OP_EQ: op_str = " == "; break;
                case OP_NE: op_str = " != "; break;
                case OP_LT: op_str = " < "; break;
                case OP_LE: op_str = " <= "; break;
                case OP_GT: op_str = " > "; break;
                case OP_GE: op_str = " >= "; break;
                case OP_LAND: op_str = " && "; break;
                case OP_LOR: op_str = " || "; break;
                default: op_str = " ? "; break;
            }
            buffer += sprintf(buffer, "(");
            buffer += format_expression_inline(expr->binaryOp.left, buffer);
            buffer += sprintf(buffer, "%s", op_str);
            buffer += format_expression_inline(expr->binaryOp.right, buffer);
            buffer += sprintf(buffer, ")");
            break;
        }
            
        case EXPR_UNARY_OP: {
            const char *op_str = "";
            switch (expr->unaryOp.op) {
                case OP_NEG: op_str = "-"; break;
                case OP_NOT: op_str = "~"; break;
                case OP_LNOT: op_str = "!"; break;
                default: op_str = "?"; break;
            }
            buffer += sprintf(buffer, "%s", op_str);
            buffer += format_expression_inline(expr->unaryOp.operand, buffer);
            break;
        }
            
        case EXPR_MEMORY_ACCESS:
            buffer += sprintf(buffer, "*");
            if (expr->memAccess.base) {
                buffer += format_expression_inline(expr->memAccess.base, buffer);
            }
            if (expr->memAccess.offset) {
                buffer += sprintf(buffer, "[");
                buffer += format_expression_inline(expr->memAccess.offset, buffer);
                buffer += sprintf(buffer, "]");
            }
            break;
            
        case EXPR_FUNCTION_CALL:
            buffer += sprintf(buffer, "%s(", expr->call.name);
            for (int i = 0; i < expr->call.argCount; i++) {
                if (i > 0) buffer += sprintf(buffer, ", ");
                buffer += format_expression_inline(expr->call.args[i], buffer);
            }
            buffer += sprintf(buffer, ")");
            break;
            
        case EXPR_CAST:
            buffer += sprintf(buffer, "(");
            if (expr->cast.targetType) {
                buffer += sprintf(buffer, "%s", expr->cast.targetType->name);
            } else {
                buffer += sprintf(buffer, "type");
            }
            buffer += sprintf(buffer, ")");
            buffer += format_expression_inline(expr->cast.expr, buffer);
            break;
            
        default:
            buffer += sprintf(buffer, "<expr>");
            break;
    }
    
    return buffer - start;
}

// MARK: - High-Level Generator API Implementation

struct PseudocodeGenerator {
    PseudocodeContext *context;
    PseudocodeConfig config;
    PseudocodeInstruction *instructions;
    int instruction_count;
    int instruction_capacity;
    char function_name[256];
    PseudocodeGeneratorOutput output;
};

PseudocodeGenerator* pseudocode_generator_create(void) {
    PseudocodeGenerator *gen = calloc(1, sizeof(PseudocodeGenerator));
    if (!gen) return NULL;
    
    gen->context = pseudocode_create_context();
    gen->instruction_capacity = 1024;
    gen->instructions = calloc(gen->instruction_capacity, sizeof(PseudocodeInstruction));
    gen->instruction_count = 0;
    gen->config.verbosity_level = 2;
    gen->config.show_types = 1;
    gen->config.show_addresses = 0;
    gen->config.simplify_expressions = 1;
    gen->config.infer_types = 1;
    gen->config.use_simple_names = 1;
    gen->config.max_inlining_depth = 3;
    gen->config.collapse_constants = 1;
    
    strcpy(gen->function_name, "unknown_function");
    
    return gen;
}

void pseudocode_generator_destroy(PseudocodeGenerator *gen) {
    if (!gen) return;
    
    if (gen->context) {
        pseudocode_free_context(gen->context);
    }
    
    if (gen->instructions) {
        free(gen->instructions);
    }
    
    if (gen->output.pseudocode) {
        free(gen->output.pseudocode);
    }
    
    if (gen->output.syntax_highlights) {
        free(gen->output.syntax_highlights);
    }
    
    free(gen);
}

void pseudocode_generator_set_config(PseudocodeGenerator *gen, PseudocodeConfig *config) {
    if (!gen || !config) return;
    gen->config = *config;
    
    if (gen->context) {
        gen->context->simplifyExpressions = config->simplify_expressions != 0;
        gen->context->generateComments = config->verbosity_level > 1;
        gen->context->reconstructLoops = config->verbosity_level > 0;
    }
}

void pseudocode_generator_add_instruction(PseudocodeGenerator *gen, PseudocodeInstruction *inst) {
    if (!gen || !inst) return;
    
    if (gen->instruction_count >= gen->instruction_capacity) {
        gen->instruction_capacity *= 2;
        gen->instructions = realloc(gen->instructions, 
                                   gen->instruction_capacity * sizeof(PseudocodeInstruction));
    }
    
    gen->instructions[gen->instruction_count++] = *inst;
}

void pseudocode_generator_set_function_name(PseudocodeGenerator *gen, const char **name) {
    if (!gen || !name || !*name) return;
    strncpy(gen->function_name, *name, sizeof(gen->function_name) - 1);
    gen->function_name[sizeof(gen->function_name) - 1] = '\0';
}

int pseudocode_generator_generate(PseudocodeGenerator *gen) {
    if (!gen || gen->instruction_count == 0) return 0;
    
    uint64_t startAddr = gen->instructions[0].address;
    PseudoFunction *func = pseudocode_generate_function(
        gen->context,
        gen->instructions,
        gen->instruction_count,
        startAddr
    );
    
    if (!func) return 0;
    
    if (strcmp(gen->function_name, "unknown_function") != 0) {
        strncpy(func->name, gen->function_name, sizeof(func->name) - 1);
    }
    
    // Generate pseudocode text (simplified - just generate a basic representation)
    char *code = calloc(65536, 1);
    char *ptr = code;
    
    snprintf(gen->output.function_signature, sizeof(gen->output.function_signature),
             "%s %s(", 
             func->returnType ? func->returnType->name : "void",
             func->name);
    
    for (int i = 0; i < func->paramCount; i++) {
        char temp[128];
        snprintf(temp, sizeof(temp), "%s%s %s",
                i > 0 ? ", " : "",
                func->paramTypes[i]->name,
                func->paramNames[i]);
        strncat(gen->output.function_signature, temp, 
                sizeof(gen->output.function_signature) - strlen(gen->output.function_signature) - 1);
    }
    strncat(gen->output.function_signature, ")", 
            sizeof(gen->output.function_signature) - strlen(gen->output.function_signature) - 1);
    
    ptr += sprintf(ptr, "%s {\n", gen->output.function_signature);
    
    for (int i = 0; i < func->statementCount && (ptr - code) < 60000; i++) {
        Statement *stmt = func->statements[i];
        if (!stmt) continue;
        
        switch (stmt->type) {
            case STMT_RETURN:
                ptr += sprintf(ptr, "    return");
                if (stmt->returnStmt.value) {
                    ptr += sprintf(ptr, " ");
                    ptr += format_expression_inline(stmt->returnStmt.value, ptr);
                }
                ptr += sprintf(ptr, ";\n");
                break;
                
            case STMT_ASSIGNMENT:
                ptr += sprintf(ptr, "    ");
                if (stmt->assignment.varName[0] != '\0') {
                    ptr += sprintf(ptr, "%s", stmt->assignment.varName);
                } else {
                    ptr += sprintf(ptr, "var_%d", i);
                }
                ptr += sprintf(ptr, " = ");
                if (stmt->assignment.value) {
                    ptr += format_expression_inline(stmt->assignment.value, ptr);
                } else {
                    ptr += sprintf(ptr, "0");
                }
                ptr += sprintf(ptr, ";\n");
                break;
                
            case STMT_IF:
                ptr += sprintf(ptr, "    if (");
                if (stmt->ifStmt.condition) {
                    ptr += format_expression_inline(stmt->ifStmt.condition, ptr);
                } else {
                    ptr += sprintf(ptr, "condition");
                }
                ptr += sprintf(ptr, ") {\n");
                ptr += sprintf(ptr, "        // true branch\n");
                ptr += sprintf(ptr, "    }\n");
                break;
                
            case STMT_WHILE:
                ptr += sprintf(ptr, "    while (");
                if (stmt->whileStmt.condition) {
                    ptr += format_expression_inline(stmt->whileStmt.condition, ptr);
                } else {
                    ptr += sprintf(ptr, "condition");
                }
                ptr += sprintf(ptr, ") {\n");
                ptr += sprintf(ptr, "        // loop body\n");
                ptr += sprintf(ptr, "    }\n");
                break;
                
            case STMT_CALL:
                ptr += sprintf(ptr, "    ");
                if (stmt->callStmt.call) {
                    ptr += format_expression_inline(stmt->callStmt.call, ptr);
                } else {
                    ptr += sprintf(ptr, "function_call()");
                }
                ptr += sprintf(ptr, ";\n");
                break;
                
            case STMT_GOTO:
                ptr += sprintf(ptr, "    goto %s;\n", stmt->gotoLabel.label);
                break;
                
            case STMT_LABEL:
                ptr += sprintf(ptr, "%s:\n", stmt->gotoLabel.label);
                break;
                
            default:
                ptr += sprintf(ptr, "    /* statement type %d */\n", stmt->type);
                break;
        }
    }
    
    ptr += sprintf(ptr, "}\n");
    
    gen->output.pseudocode = code;
    gen->output.instruction_count = gen->instruction_count;
    gen->output.variable_count = func->localCount;
    gen->output.complexity = func->statementCount;
    gen->output.loop_count = 0;
    gen->output.conditional_count = 0;
    int basic_blocks = 1;
    
    for (int i = 0; i < func->statementCount; i++) {
        if (!func->statements[i]) continue;
        
        Statement *stmt = func->statements[i];
        switch (stmt->type) {
            case STMT_IF:
                gen->output.conditional_count++;
                basic_blocks += 2;
                if (stmt->ifStmt.elseCount > 0) {
                    basic_blocks++;
                }
                break;
                
            case STMT_WHILE:
            case STMT_FOR:
                gen->output.loop_count++;
                basic_blocks += 2;
                break;
                
            case STMT_GOTO:
                basic_blocks++;
                break;
                
            case STMT_LABEL:
                basic_blocks++;
                break;
                
            case STMT_RETURN:
                basic_blocks++;
                break;
                
            case STMT_SWITCH:
                if (stmt->switchStmt.caseCount > 0) {
                    basic_blocks += stmt->switchStmt.caseCount + 1;
                }
                break;
                
            default:
                break;
        }
    }
    
    gen->output.basic_block_count = basic_blocks;
    
    int max_highlights = (strlen(code) / 10) + 100;
    gen->output.syntax_highlights = calloc(max_highlights, sizeof(SyntaxHighlight));
    gen->output.highlight_count = 0;
    
    char *search = code;
    int offset = 0;
    
    const char *keywords[] = {"if", "else", "while", "for", "do", "switch", "case", "break", 
                              "continue", "return", "goto", "default", NULL};
    
    const char *types[] = {"void", "int", "uint", "int8", "int16", "int32", "int64",
                          "uint8", "uint16", "uint32", "uint64", "float", "double",
                          "char", "bool", NULL};
    
    while (*search && gen->output.highlight_count < max_highlights - 1) {
        while (*search == ' ' || *search == '\t' || *search == '\n') {
            search++;
            offset++;
        }
        
        if (*search == '\0') break;
        
        for (int k = 0; keywords[k] != NULL; k++) {
            int kwlen = strlen(keywords[k]);
            if (strncmp(search, keywords[k], kwlen) == 0 &&
                (search[kwlen] == ' ' || search[kwlen] == '(' || search[kwlen] == '\n' || search[kwlen] == ';')) {
                
                SyntaxHighlight *hl = &gen->output.syntax_highlights[gen->output.highlight_count++];
                hl->start = offset;
                hl->length = kwlen;
                hl->type = HIGHLIGHT_KEYWORD;
                search += kwlen;
                offset += kwlen;
                goto continue_loop;
            }
        }
        
        for (int t = 0; types[t] != NULL; t++) {
            int typelen = strlen(types[t]);
            if (strncmp(search, types[t], typelen) == 0 &&
                (search[typelen] == ' ' || search[typelen] == '\n' || search[typelen] == '*')) {
                
                SyntaxHighlight *hl = &gen->output.syntax_highlights[gen->output.highlight_count++];
                hl->start = offset;
                hl->length = typelen;
                hl->type = HIGHLIGHT_TYPE;
                search += typelen;
                offset += typelen;
                goto continue_loop;
            }
        }
        
        if (search[0] == '0' && (search[1] == 'x' || search[1] == 'X')) {
            int len = 2;
            while (search[len] && ((search[len] >= '0' && search[len] <= '9') ||
                                 (search[len] >= 'a' && search[len] <= 'f') ||
                                 (search[len] >= 'A' && search[len] <= 'F'))) {
                len++;
            }
            
            if (gen->output.highlight_count < max_highlights - 1) {
                SyntaxHighlight *hl = &gen->output.syntax_highlights[gen->output.highlight_count++];
                hl->start = offset;
                hl->length = len;
                hl->type = HIGHLIGHT_CONSTANT;
            }
            search += len;
            offset += len;
            continue;
        }
        
        if ((search[0] == 'x' || search[0] == 'w') && search[1] >= '0' && search[1] <= '9') {
            int len = 2;
            if (search[2] >= '0' && search[2] <= '9') len = 3;
            
            if (gen->output.highlight_count < max_highlights - 1) {
                SyntaxHighlight *hl = &gen->output.syntax_highlights[gen->output.highlight_count++];
                hl->start = offset;
                hl->length = len;
                hl->type = HIGHLIGHT_REGISTER;
            }
            search += len;
            offset += len;
            continue;
        }
        
        if (strncmp(search, "sp", 2) == 0 || strncmp(search, "fp", 2) == 0 ||
            strncmp(search, "lr", 2) == 0 || strncmp(search, "pc", 2) == 0) {
            if (gen->output.highlight_count < max_highlights - 1) {
                SyntaxHighlight *hl = &gen->output.syntax_highlights[gen->output.highlight_count++];
                hl->start = offset;
                hl->length = 2;
                hl->type = HIGHLIGHT_REGISTER;
            }
            search += 2;
            offset += 2;
            continue;
        }
        
        if ((*search >= 'a' && *search <= 'z') || (*search >= 'A' && *search <= 'Z') || *search == '_') {
            int len = 0;
            while ((search[len] >= 'a' && search[len] <= 'z') ||
                   (search[len] >= 'A' && search[len] <= 'Z') ||
                   (search[len] >= '0' && search[len] <= '9') ||
                   search[len] == '_') {
                len++;
            }
            
            int skip = len;
            while (search[skip] == ' ' || search[skip] == '\t') skip++;
            
            if (search[skip] == '(') {
                if (gen->output.highlight_count < max_highlights - 1) {
                    SyntaxHighlight *hl = &gen->output.syntax_highlights[gen->output.highlight_count++];
                    hl->start = offset;
                    hl->length = len;
                    hl->type = HIGHLIGHT_FUNCTION;
                }
            }
            search += len;
            offset += len;
            continue;
        }
        
        continue_loop:
        if (*search == '\0') break;
        search++;
        offset++;
    }
    
    pseudocode_free_function(func);
    
    return 1;
}

PseudocodeGeneratorOutput* pseudocode_generator_get_output(PseudocodeGenerator *gen) {
    if (!gen) return NULL;
    return &gen->output;
}

