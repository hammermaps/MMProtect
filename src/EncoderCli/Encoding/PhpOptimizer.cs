using System.Text;

namespace MmProtect.EncoderCli.Encoding;

/// <summary>
/// Optimizer passes that can be applied to PHP source before encryption.
/// </summary>
[Flags]
public enum OptimizePasses
{
    None            = 0,
    Comments        = 1 << 0,
    Whitespace      = 1 << 1,
    ConstantFolding = 1 << 2,
    DeadCode        = 1 << 3,
    All             = Comments | Whitespace | ConstantFolding | DeadCode,
}

/// <summary>
/// Token-level PHP optimizer: comment stripping, whitespace collapsing,
/// constant folding, and dead code elimination.
/// </summary>
public static class PhpOptimizer
{
    // ── Public API ────────────────────────────────────────────────────────────

    public static string Optimize(string phpSource, OptimizePasses passes)
    {
        if (passes == OptimizePasses.None) return phpSource;
        var tokens = Tokenize(phpSource);
        if (passes.HasFlag(OptimizePasses.ConstantFolding))
            tokens = FoldConstants(tokens);
        if (passes.HasFlag(OptimizePasses.DeadCode))
            tokens = EliminateDeadCode(tokens);
        return Reconstruct(tokens,
            stripComments:      passes.HasFlag(OptimizePasses.Comments),
            collapseWhitespace: passes.HasFlag(OptimizePasses.Whitespace));
    }

    /// <summary>
    /// Parse a pass specifier string like "all", "none", "constants,deadcode".
    /// Recognized names: all, none, comments, whitespace/ws, constants/constantfolding/folding, deadcode/dead.
    /// </summary>
    public static OptimizePasses ParsePasses(string? spec)
    {
        if (string.IsNullOrWhiteSpace(spec) ||
            spec.Equals("all", StringComparison.OrdinalIgnoreCase))
            return OptimizePasses.All;
        if (spec.Equals("none", StringComparison.OrdinalIgnoreCase))
            return OptimizePasses.None;
        var result = OptimizePasses.None;
        foreach (var part in spec.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            result |= part.ToLowerInvariant() switch
            {
                "comments" or "comment"                             => OptimizePasses.Comments,
                "whitespace" or "ws"                                => OptimizePasses.Whitespace,
                "constants" or "constantfolding" or "folding"       => OptimizePasses.ConstantFolding,
                "deadcode" or "dead"                                => OptimizePasses.DeadCode,
                _                                                   => OptimizePasses.None,
            };
        }
        return result;
    }

    // ── Token types ───────────────────────────────────────────────────────────

    private enum TK
    {
        Whitespace, LineComment, BlockComment,
        IntLit, FloatLit,
        SingleStr,      // 'foo' — no interpolation, foldable for concat
        DoubleStr,      // "foo" — may contain interpolation, opaque
        Heredoc, Nowdoc,
        Ident,          // identifier, keyword, true, false, null
        Variable,       // $name or $$name
        Plus, Minus, Star, Slash, Percent, StarStar, Dot,
        Bang,
        AmpAmp, PipePipe,
        EqEq, EqEqEq, BangEq, BangEqEq,
        Lt, Gt, LtEq, GtEq,
        LBrace, RBrace,
        LParen, RParen,
        LSq, RSq,
        Semi, Comma, Colon, Question,
        Other,
    }

    private readonly record struct Token(TK Kind, string Value);

    // ── Tokenizer ─────────────────────────────────────────────────────────────

    private static List<Token> Tokenize(string src)
    {
        var tokens = new List<Token>(src.Length / 4);
        int i = 0, len = src.Length;

        while (i < len)
        {
            char c = src[i];

            // Whitespace
            if (c is ' ' or '\t' or '\r' or '\n')
            {
                int start = i;
                while (i < len && src[i] is ' ' or '\t' or '\r' or '\n') i++;
                tokens.Add(new Token(TK.Whitespace, src[start..i]));
                continue;
            }

            // Line comment //
            if (c == '/' && i + 1 < len && src[i + 1] == '/')
            {
                int start = i;
                while (i < len && src[i] != '\n') i++;
                tokens.Add(new Token(TK.LineComment, src[start..i]));
                continue;
            }

            // Hash comment (not PHP 8 attribute #[...)
            if (c == '#' && !(i + 1 < len && src[i + 1] == '['))
            {
                int start = i;
                while (i < len && src[i] != '\n') i++;
                tokens.Add(new Token(TK.LineComment, src[start..i]));
                continue;
            }

            // Block comment /* ... */
            if (c == '/' && i + 1 < len && src[i + 1] == '*')
            {
                int start = i; i += 2;
                while (i + 1 < len && !(src[i] == '*' && src[i + 1] == '/')) i++;
                if (i + 1 < len) i += 2;
                tokens.Add(new Token(TK.BlockComment, src[start..i]));
                continue;
            }

            // Single-quoted string
            if (c == '\'')
            {
                int start = i++;
                while (i < len && src[i] != '\'')
                {
                    if (src[i] == '\\' && i + 1 < len) i += 2;
                    else i++;
                }
                if (i < len) i++;
                tokens.Add(new Token(TK.SingleStr, src[start..i]));
                continue;
            }

            // Double-quoted string (opaque — may contain variable interpolation)
            if (c == '"')
            {
                int start = i++;
                while (i < len && src[i] != '"')
                {
                    if (src[i] == '\\' && i + 1 < len) i += 2;
                    else i++;
                }
                if (i < len) i++;
                tokens.Add(new Token(TK.DoubleStr, src[start..i]));
                continue;
            }

            // Heredoc / Nowdoc <<<
            if (c == '<' && i + 2 < len && src[i + 1] == '<' && src[i + 2] == '<')
            {
                int start = i; i += 3;
                while (i < len && src[i] == ' ') i++;
                bool isNowdoc = i < len && src[i] == '\'';
                if (isNowdoc) i++;
                int labelStart = i;
                while (i < len && (char.IsLetterOrDigit(src[i]) || src[i] == '_')) i++;
                string label = src[labelStart..i];
                if (isNowdoc && i < len && src[i] == '\'') i++;
                while (i < len && src[i] != '\n') i++;
                if (i < len) i++;
                // Scan for closing label at line start
                while (i < len)
                {
                    if (i + label.Length <= len &&
                        src.AsSpan(i, label.Length).SequenceEqual(label.AsSpan()))
                    {
                        int after = i + label.Length;
                        if (after >= len || src[after] == ';' || src[after] == '\n' || src[after] == '\r')
                        {
                            i = after;
                            while (i < len && src[i] != '\n') i++;
                            if (i < len) i++;
                            break;
                        }
                    }
                    while (i < len && src[i] != '\n') i++;
                    if (i < len) i++;
                }
                tokens.Add(new Token(isNowdoc ? TK.Nowdoc : TK.Heredoc, src[start..i]));
                continue;
            }

            // Numeric literal
            if (char.IsDigit(c))
            {
                int start = i;
                bool isFloat = false;
                if (c == '0' && i + 1 < len && src[i + 1] is 'x' or 'X')
                {
                    i += 2;
                    while (i < len && (IsHexDigit(src[i]) || src[i] == '_')) i++;
                }
                else if (c == '0' && i + 1 < len && src[i + 1] is 'b' or 'B')
                {
                    i += 2;
                    while (i < len && (src[i] is '0' or '1' or '_')) i++;
                }
                else if (c == '0' && i + 1 < len && src[i + 1] is 'o' or 'O')
                {
                    i += 2;
                    while (i < len && (src[i] >= '0' && src[i] <= '7' || src[i] == '_')) i++;
                }
                else
                {
                    while (i < len && (char.IsDigit(src[i]) || src[i] == '_')) i++;
                    if (i < len && src[i] == '.' && i + 1 < len && char.IsDigit(src[i + 1]))
                    {
                        isFloat = true; i++;
                        while (i < len && (char.IsDigit(src[i]) || src[i] == '_')) i++;
                    }
                    if (i < len && src[i] is 'e' or 'E')
                    {
                        isFloat = true; i++;
                        if (i < len && src[i] is '+' or '-') i++;
                        while (i < len && char.IsDigit(src[i])) i++;
                    }
                }
                tokens.Add(new Token(isFloat ? TK.FloatLit : TK.IntLit, src[start..i]));
                continue;
            }

            // Variable $name
            if (c == '$')
            {
                int start = i++;
                while (i < len && (char.IsLetterOrDigit(src[i]) || src[i] == '_')) i++;
                tokens.Add(new Token(TK.Variable, src[start..i]));
                continue;
            }

            // Identifier / keyword
            if (char.IsLetter(c) || c == '_')
            {
                int start = i;
                while (i < len && (char.IsLetterOrDigit(src[i]) || src[i] == '_')) i++;
                tokens.Add(new Token(TK.Ident, src[start..i]));
                continue;
            }

            // Multi-char and single-char operators / punctuation
            switch (c)
            {
                case '+':
                    if (Next(src, i) == '+') { tokens.Add(new Token(TK.Other, "++")); i += 2; }
                    else if (Next(src, i) == '=') { tokens.Add(new Token(TK.Other, "+=")); i += 2; }
                    else { tokens.Add(new Token(TK.Plus, "+")); i++; }
                    break;
                case '-':
                    if (Next(src, i) == '-') { tokens.Add(new Token(TK.Other, "--")); i += 2; }
                    else if (Next(src, i) == '=') { tokens.Add(new Token(TK.Other, "-=")); i += 2; }
                    else if (Next(src, i) == '>') { tokens.Add(new Token(TK.Other, "->")); i += 2; }
                    else { tokens.Add(new Token(TK.Minus, "-")); i++; }
                    break;
                case '*':
                    if (Next(src, i) == '*')
                    {
                        if (i + 2 < len && src[i + 2] == '=') { tokens.Add(new Token(TK.Other, "**=")); i += 3; }
                        else { tokens.Add(new Token(TK.StarStar, "**")); i += 2; }
                    }
                    else if (Next(src, i) == '=') { tokens.Add(new Token(TK.Other, "*=")); i += 2; }
                    else { tokens.Add(new Token(TK.Star, "*")); i++; }
                    break;
                case '/':
                    if (Next(src, i) == '=') { tokens.Add(new Token(TK.Other, "/=")); i += 2; }
                    else { tokens.Add(new Token(TK.Slash, "/")); i++; }
                    break;
                case '%':
                    if (Next(src, i) == '=') { tokens.Add(new Token(TK.Other, "%=")); i += 2; }
                    else { tokens.Add(new Token(TK.Percent, "%")); i++; }
                    break;
                case '.':
                    if (Next(src, i) == '=') { tokens.Add(new Token(TK.Other, ".=")); i += 2; }
                    else if (Next(src, i) == '.' && i + 2 < len && src[i + 2] == '.') { tokens.Add(new Token(TK.Other, "...")); i += 3; }
                    else { tokens.Add(new Token(TK.Dot, ".")); i++; }
                    break;
                case '!':
                    if (Next(src, i) == '=')
                    {
                        if (i + 2 < len && src[i + 2] == '=') { tokens.Add(new Token(TK.BangEqEq, "!==")); i += 3; }
                        else { tokens.Add(new Token(TK.BangEq, "!=")); i += 2; }
                    }
                    else { tokens.Add(new Token(TK.Bang, "!")); i++; }
                    break;
                case '&':
                    if (Next(src, i) == '&') { tokens.Add(new Token(TK.AmpAmp, "&&")); i += 2; }
                    else if (Next(src, i) == '=') { tokens.Add(new Token(TK.Other, "&=")); i += 2; }
                    else { tokens.Add(new Token(TK.Other, "&")); i++; }
                    break;
                case '|':
                    if (Next(src, i) == '|') { tokens.Add(new Token(TK.PipePipe, "||")); i += 2; }
                    else if (Next(src, i) == '=') { tokens.Add(new Token(TK.Other, "|=")); i += 2; }
                    else { tokens.Add(new Token(TK.Other, "|")); i++; }
                    break;
                case '=':
                    if (Next(src, i) == '=')
                    {
                        if (i + 2 < len && src[i + 2] == '=') { tokens.Add(new Token(TK.EqEqEq, "===")); i += 3; }
                        else { tokens.Add(new Token(TK.EqEq, "==")); i += 2; }
                    }
                    else if (Next(src, i) == '>') { tokens.Add(new Token(TK.Other, "=>")); i += 2; }
                    else { tokens.Add(new Token(TK.Other, "=")); i++; }
                    break;
                case '<':
                    if (Next(src, i) == '=')
                    {
                        if (i + 2 < len && src[i + 2] == '>') { tokens.Add(new Token(TK.Other, "<=>")); i += 3; }
                        else { tokens.Add(new Token(TK.LtEq, "<=")); i += 2; }
                    }
                    else if (Next(src, i) == '<')
                    {
                        if (i + 2 < len && src[i + 2] == '=') { tokens.Add(new Token(TK.Other, "<<=")); i += 3; }
                        else { tokens.Add(new Token(TK.Other, "<<")); i += 2; }
                    }
                    else { tokens.Add(new Token(TK.Lt, "<")); i++; }
                    break;
                case '>':
                    if (Next(src, i) == '=') { tokens.Add(new Token(TK.GtEq, ">=")); i += 2; }
                    else if (Next(src, i) == '>')
                    {
                        if (i + 2 < len && src[i + 2] == '=') { tokens.Add(new Token(TK.Other, ">>=")); i += 3; }
                        else { tokens.Add(new Token(TK.Other, ">>")); i += 2; }
                    }
                    else { tokens.Add(new Token(TK.Gt, ">")); i++; }
                    break;
                case '?':
                    if (Next(src, i) == '?')
                    {
                        if (i + 2 < len && src[i + 2] == '=') { tokens.Add(new Token(TK.Other, "??=")); i += 3; }
                        else { tokens.Add(new Token(TK.Other, "??")); i += 2; }
                    }
                    else if (Next(src, i) == '-' && i + 2 < len && src[i + 2] == '>')
                    {
                        tokens.Add(new Token(TK.Other, "?->")); i += 3;
                    }
                    else { tokens.Add(new Token(TK.Question, "?")); i++; }
                    break;
                case ':':
                    if (Next(src, i) == ':') { tokens.Add(new Token(TK.Other, "::")); i += 2; }
                    else { tokens.Add(new Token(TK.Colon, ":")); i++; }
                    break;
                case '{': tokens.Add(new Token(TK.LBrace, "{")); i++; break;
                case '}': tokens.Add(new Token(TK.RBrace, "}")); i++; break;
                case '(': tokens.Add(new Token(TK.LParen, "(")); i++; break;
                case ')': tokens.Add(new Token(TK.RParen, ")")); i++; break;
                case '[': tokens.Add(new Token(TK.LSq, "[")); i++; break;
                case ']': tokens.Add(new Token(TK.RSq, "]")); i++; break;
                case ';': tokens.Add(new Token(TK.Semi, ";")); i++; break;
                case ',': tokens.Add(new Token(TK.Comma, ",")); i++; break;
                default:  tokens.Add(new Token(TK.Other, c.ToString())); i++; break;
            }
        }

        return tokens;
    }

    private static char Next(string src, int i) =>
        i + 1 < src.Length ? src[i + 1] : '\0';

    private static bool IsHexDigit(char c) =>
        char.IsDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');

    // ── Constant folding ──────────────────────────────────────────────────────

    private static List<Token> FoldConstants(List<Token> tokens)
    {
        var result = new List<Token>(tokens.Count);
        int i = 0;

        while (i < tokens.Count)
        {
            // !true → false, !false → true
            if (tokens[i].Kind == TK.Bang)
            {
                int j = SkipWs(tokens, i + 1);
                if (j < tokens.Count && tokens[j].Kind == TK.Ident)
                {
                    var bv = tokens[j].Value.ToLowerInvariant();
                    if (bv == "true")  { result.Add(new Token(TK.Ident, "false")); i = j + 1; continue; }
                    if (bv == "false") { result.Add(new Token(TK.Ident, "true"));  i = j + 1; continue; }
                }
            }

            // INT_OP INT or 'str' . 'str'
            if (tokens[i].Kind is TK.IntLit or TK.SingleStr)
            {
                int j = SkipWs(tokens, i + 1);
                if (j < tokens.Count && IsArithOrDotOp(tokens[j], tokens[i].Kind))
                {
                    int k = SkipWs(tokens, j + 1);
                    if (k < tokens.Count && tokens[k].Kind == tokens[i].Kind)
                    {
                        if (TryFoldBinaryOp(tokens[i], tokens[j], tokens[k], out var folded))
                        {
                            result.Add(folded);
                            i = k + 1;
                            continue;
                        }
                    }
                }
            }

            result.Add(tokens[i]);
            i++;
        }

        return result;
    }

    private static bool IsArithOrDotOp(Token op, TK leftKind) =>
        leftKind == TK.IntLit
            ? op.Kind is TK.Plus or TK.Minus or TK.Star or TK.Slash or TK.Percent or TK.StarStar
            : op.Kind == TK.Dot;

    private static bool TryFoldBinaryOp(Token left, Token op, Token right, out Token folded)
    {
        folded = default;

        if (left.Kind == TK.IntLit && right.Kind == TK.IntLit)
        {
            if (!TryParsePhpInt(left.Value, out long lv) ||
                !TryParsePhpInt(right.Value, out long rv))
                return false;

            long? r = op.Kind switch
            {
                TK.Plus     => lv + rv,
                TK.Minus    => lv - rv,
                TK.Star     => lv * rv,
                TK.Percent  => rv != 0 ? lv % rv : (long?)null,
                TK.StarStar => rv >= 0 && rv < 62 ? LongPow(lv, (int)rv) : (long?)null,
                TK.Slash    => rv != 0 && lv % rv == 0 ? lv / rv : (long?)null,
                _           => null,
            };
            if (r is null) return false;
            folded = new Token(TK.IntLit, r.Value.ToString());
            return true;
        }

        if (left.Kind == TK.SingleStr && right.Kind == TK.SingleStr && op.Kind == TK.Dot)
        {
            var combined = "'" + EncodeSingleQuoted(
                DecodeSingleQuoted(left.Value) + DecodeSingleQuoted(right.Value)) + "'";
            folded = new Token(TK.SingleStr, combined);
            return true;
        }

        return false;
    }

    private static bool TryParsePhpInt(string s, out long value)
    {
        s = s.Replace("_", "");
        if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
            return long.TryParse(s[2..], System.Globalization.NumberStyles.HexNumber, null, out value);
        if (s.StartsWith("0b", StringComparison.OrdinalIgnoreCase))
        {
            try { value = Convert.ToInt64(s[2..], 2); return true; }
            catch { value = 0; return false; }
        }
        if (s.StartsWith("0o", StringComparison.OrdinalIgnoreCase))
        {
            try { value = Convert.ToInt64(s[2..], 8); return true; }
            catch { value = 0; return false; }
        }
        return long.TryParse(s, out value);
    }

    private static long LongPow(long b, int e)
    {
        long r = 1;
        checked { for (int n = 0; n < e; n++) r *= b; }
        return r;
    }

    private static string DecodeSingleQuoted(string token) =>
        token[1..^1].Replace("\\'", "'").Replace("\\\\", "\\");

    private static string EncodeSingleQuoted(string s) =>
        s.Replace("\\", "\\\\").Replace("'", "\\'");

    // ── Dead code elimination ─────────────────────────────────────────────────

    private static List<Token> EliminateDeadCode(List<Token> tokens)
    {
        var result = new List<Token>(tokens.Count);
        int i = 0;
        int braceDepth = 0;

        while (i < tokens.Count)
        {
            // if (false/true/0/1) { ... } [else { ... }]
            if (IsIdentValue(tokens[i], "if"))
            {
                if (TryMatchSimpleIfCondition(tokens, i + 1, out int afterParen, out bool condTrue))
                {
                    HandleConstantIf(tokens, ref i, afterParen, condTrue, result, ref braceDepth);
                    continue;
                }
            }

            var tok = tokens[i];
            if (tok.Kind == TK.LBrace) braceDepth++;
            else if (tok.Kind == TK.RBrace) braceDepth--;
            result.Add(tok);

            // After return/throw/exit/die statement, code until } is dead.
            if (tok.Kind == TK.Ident && IsExitLike(tok.Value))
            {
                // Collect rest of statement (to ';' at paren depth 0)
                int parenD = 0;
                i++;
                while (i < tokens.Count)
                {
                    var t = tokens[i]; i++;
                    result.Add(t);
                    if (t.Kind == TK.LParen) parenD++;
                    else if (t.Kind == TK.RParen) parenD--;
                    else if (t.Kind == TK.LBrace) braceDepth++;
                    else if (t.Kind == TK.RBrace) braceDepth--;
                    else if (t.Kind == TK.Semi && parenD == 0) break;
                }
                // Skip all dead tokens until the } that closes the current block
                SkipUntilBlockClose(tokens, ref i, ref braceDepth, result);
                continue;
            }

            i++;
        }

        return result;
    }

    private static bool IsIdentValue(Token tok, string value) =>
        tok.Kind == TK.Ident &&
        string.Equals(tok.Value, value, StringComparison.OrdinalIgnoreCase);

    private static bool IsExitLike(string ident) =>
        string.Equals(ident, "return", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(ident, "throw",  StringComparison.OrdinalIgnoreCase) ||
        string.Equals(ident, "exit",   StringComparison.OrdinalIgnoreCase) ||
        string.Equals(ident, "die",    StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Matches: WS? ( WS? (true|false|0|non-zero-int) WS? )
    /// Returns true when the condition is a single compile-time constant.
    /// </summary>
    private static bool TryMatchSimpleIfCondition(
        List<Token> tokens, int j, out int afterParen, out bool condTrue)
    {
        afterParen = j; condTrue = false;
        j = SkipWs(tokens, j);
        if (j >= tokens.Count || tokens[j].Kind != TK.LParen) return false;
        j++;
        j = SkipWs(tokens, j);
        if (j >= tokens.Count) return false;

        var cond = tokens[j];
        if (cond.Kind == TK.Ident)
        {
            var v = cond.Value.ToLowerInvariant();
            if (v != "true" && v != "false") return false;
            condTrue = v == "true";
        }
        else if (cond.Kind == TK.IntLit)
        {
            if (!TryParsePhpInt(cond.Value, out long iv)) return false;
            condTrue = iv != 0;
        }
        else return false;

        j++;
        j = SkipWs(tokens, j);
        if (j >= tokens.Count || tokens[j].Kind != TK.RParen) return false;
        afterParen = j + 1;
        return true;
    }

    private static void HandleConstantIf(
        List<Token> tokens, ref int i, int afterParen,
        bool condTrue, List<Token> result, ref int braceDepth)
    {
        i = SkipWs(tokens, afterParen);

        if (condTrue)
        {
            // Keep if-body, skip else
            EmitBlock(tokens, ref i, result, ref braceDepth);
            SkipOptionalElse(tokens, ref i, ref braceDepth);
        }
        else
        {
            // Skip if-body, keep else body (if any)
            SkipBlock(tokens, ref i, ref braceDepth);
            KeepOptionalElse(tokens, ref i, result, ref braceDepth);
        }
    }

    /// <summary>Emit the next block (braced or single statement) into result.</summary>
    private static void EmitBlock(List<Token> tokens, ref int i, List<Token> result, ref int braceDepth)
    {
        if (i >= tokens.Count) return;
        if (tokens[i].Kind == TK.LBrace)
        {
            i++; braceDepth++; // skip opening {
            int depth = 1;
            while (i < tokens.Count && depth > 0)
            {
                var t = tokens[i++];
                if (t.Kind == TK.LBrace) { depth++; braceDepth++; }
                else if (t.Kind == TK.RBrace) { depth--; braceDepth--; if (depth == 0) return; } // skip closing }
                result.Add(t);
            }
        }
        else
        {
            // Single statement: emit up to and including ';'
            int parenD = 0;
            while (i < tokens.Count)
            {
                var t = tokens[i++];
                result.Add(t);
                if (t.Kind == TK.LParen) parenD++;
                else if (t.Kind == TK.RParen) parenD--;
                else if (t.Kind == TK.Semi && parenD == 0) return;
            }
        }
    }

    /// <summary>Skip the next block (braced or single statement).</summary>
    private static void SkipBlock(List<Token> tokens, ref int i, ref int braceDepth)
    {
        if (i >= tokens.Count) return;
        if (tokens[i].Kind == TK.LBrace)
        {
            i++; // skip {
            int depth = 1;
            while (i < tokens.Count && depth > 0)
            {
                var t = tokens[i++];
                if (t.Kind == TK.LBrace) { depth++; braceDepth++; }
                else if (t.Kind == TK.RBrace) { depth--; braceDepth--; }
            }
        }
        else
        {
            int parenD = 0;
            while (i < tokens.Count)
            {
                var t = tokens[i++];
                if (t.Kind == TK.LParen) parenD++;
                else if (t.Kind == TK.RParen) parenD--;
                else if (t.Kind == TK.Semi && parenD == 0) return;
            }
        }
    }

    /// <summary>Skip optional else/elseif clause after if-body.</summary>
    private static void SkipOptionalElse(List<Token> tokens, ref int i, ref int braceDepth)
    {
        int j = SkipWs(tokens, i);
        if (j >= tokens.Count) return;
        if (!IsIdentValue(tokens[j], "else") && !IsIdentValue(tokens[j], "elseif")) return;
        i = j + 1;
        // For 'elseif' or 'else if': skip the remainder
        int k = SkipWs(tokens, i);
        if (k < tokens.Count && IsIdentValue(tokens[k], "if"))
        {
            // else if (...) body → skip it recursively
            if (TryMatchSimpleIfCondition(tokens, k + 1, out int ap, out _))
            {
                i = ap;
                SkipBlock(tokens, ref i, ref braceDepth);
                SkipOptionalElse(tokens, ref i, ref braceDepth);
            }
            else
            {
                // Unknown condition — skip the whole rest conservatively
                // (find matching brace to end the else-if chain)
                SkipBlock(tokens, ref i, ref braceDepth);
            }
        }
        else
        {
            i = k < tokens.Count ? k : i;
            SkipBlock(tokens, ref i, ref braceDepth);
        }
    }

    /// <summary>Keep optional else/elseif clause (emit its body) after a skipped if-body.</summary>
    private static void KeepOptionalElse(
        List<Token> tokens, ref int i, List<Token> result, ref int braceDepth)
    {
        int j = SkipWs(tokens, i);
        if (j >= tokens.Count) return;
        if (!IsIdentValue(tokens[j], "else") && !IsIdentValue(tokens[j], "elseif")) return;
        i = j + 1;
        // For 'else if': keep the entire if-statement as-is
        int k = SkipWs(tokens, i);
        if (k < tokens.Count && IsIdentValue(tokens[k], "if"))
        {
            if (TryMatchSimpleIfCondition(tokens, k + 1, out int ap, out bool ct))
            {
                i = k; // reprocess from 'if'
                HandleConstantIf(tokens, ref i, ap, ct, result, ref braceDepth);
            }
            else
            {
                // Emit rest verbatim
                i = k;
                EmitBlock(tokens, ref i, result, ref braceDepth);
            }
        }
        else
        {
            i = k < tokens.Count ? k : i;
            EmitBlock(tokens, ref i, result, ref braceDepth);
        }
    }

    /// <summary>
    /// Skip all tokens until the '}' that closes the current brace depth,
    /// then emit that closing '}'.
    /// </summary>
    private static void SkipUntilBlockClose(
        List<Token> tokens, ref int i, ref int braceDepth, List<Token> result)
    {
        int deadDepth = braceDepth;
        while (i < tokens.Count)
        {
            var tok = tokens[i++];
            if (tok.Kind == TK.LBrace) braceDepth++;
            else if (tok.Kind == TK.RBrace)
            {
                braceDepth--;
                if (braceDepth < deadDepth)
                {
                    result.Add(tok); // emit the closing }
                    return;
                }
            }
        }
    }

    // ── Reconstruction ────────────────────────────────────────────────────────

    private static string Reconstruct(List<Token> tokens, bool stripComments, bool collapseWhitespace)
    {
        if (!stripComments && !collapseWhitespace)
        {
            var sb0 = new StringBuilder();
            foreach (var t in tokens) sb0.Append(t.Value);
            return sb0.ToString();
        }

        var sb = new StringBuilder(tokens.Count * 4);
        bool lastWasSpace = false;
        bool lastWasNewline = false;

        foreach (var tok in tokens)
        {
            if (stripComments && tok.Kind is TK.LineComment or TK.BlockComment)
                continue;

            if (collapseWhitespace && tok.Kind == TK.Whitespace)
            {
                bool hasNewline = tok.Value.Contains('\n');
                if (hasNewline)
                {
                    if (!lastWasNewline) { sb.Append('\n'); lastWasNewline = true; }
                    lastWasSpace = false;
                }
                else
                {
                    if (!lastWasSpace && !lastWasNewline) { sb.Append(' '); lastWasSpace = true; }
                }
                continue;
            }

            sb.Append(tok.Value);
            if (tok.Value.Length > 0)
            {
                var last = tok.Value[^1];
                lastWasNewline = last == '\n';
                lastWasSpace   = !lastWasNewline && last is ' ' or '\t';
            }
        }

        return sb.ToString();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static int SkipWs(List<Token> tokens, int i)
    {
        while (i < tokens.Count && tokens[i].Kind == TK.Whitespace) i++;
        return i;
    }
}
