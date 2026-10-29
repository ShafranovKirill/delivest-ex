Definitions.

D = [0-9]
L = [a-z_]
WS = [\s\t\r\n]

Rules.

{WS}+ : skip_token.
#[^\n]* : skip_token.
{D}{D}?:{D}{D} : {token, {clock, TokenLoc, TokenChars}}.
x{D}+ : {token, {times, TokenLoc, list_to_integer(tl(TokenChars))}}.
{D}+\.{D}{D}? : {token, {money, TokenLoc, kopecks(TokenChars)}}.
{D}+ : {token, {int, TokenLoc, list_to_integer(TokenChars)}}.
"[^"\n]*" : {token, {string, TokenLoc, unquote(TokenChars)}}.
>= : {token, {cmp, TokenLoc, '>='}}.
<= : {token, {cmp, TokenLoc, '<='}}.
> : {token, {cmp, TokenLoc, '>'}}.
< : {token, {cmp, TokenLoc, '<'}}.
= : {token, {cmp, TokenLoc, '='}}.
\.\. : {token, {'..', TokenLoc}}.
\( : {token, {'(', TokenLoc}}.
\) : {token, {')', TokenLoc}}.
, : {token, {',', TokenLoc}}.
\% : {token, {'%', TokenLoc}}.
{L}+ : {token, word(TokenChars, TokenLoc)}.

Erlang code.

-define(KEYWORDS, ["when", "then", "and", "or", "not", "in", "on", "max", "rub", "x",
                   "has", "subtotal", "quantity", "fulfillment", "time", "weekday",
                   "discount", "gift", "price"]).

kopecks(Chars) ->
    [Rubles, Kopecks] = string:split(Chars, "."),
    list_to_integer(Rubles) * 100 + list_to_integer(lists:flatten(string:pad(Kopecks, 2, trailing, $0))).

unquote(Chars) -> lists:sublist(Chars, 2, length(Chars) - 2).

word(Chars, Loc) ->
    case lists:member(Chars, ?KEYWORDS) of
        true -> {list_to_atom(Chars), Loc};
        false -> {ident, Loc, Chars}
    end.
