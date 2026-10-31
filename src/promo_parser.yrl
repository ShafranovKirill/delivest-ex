Nonterminals
program condition conj neg atom amount sum effects effect target cap strings idents.

Terminals
'when' 'then' 'and' 'or' 'not' 'in' 'on' 'max' 'rub' 'x'
'has' 'subtotal' 'quantity' 'fulfillment' 'time' 'weekday'
'discount' 'gift' 'price'
'(' ')' ',' '%' '..'
int money string ident clock cmp times.

Rootsymbol program.

program -> 'then' effects : {nil, '$2'}.
program -> 'when' condition 'then' effects : {'$2', '$4'}.

condition -> conj : '$1'.
condition -> condition 'or' conj : {'or', '$1', '$3'}.

conj -> neg : '$1'.
conj -> conj 'and' neg : {'and', '$1', '$3'}.

neg -> 'not' neg : {'not', '$2'}.
neg -> atom : '$1'.

atom -> '(' condition ')' : '$2'.
atom -> 'subtotal' cmp sum : {subtotal, value('$2'), element(1, '$3')}.
atom -> 'quantity' cmp int : {quantity, value('$2'), value('$3')}.
atom -> 'has' string amount : {has, located('$2'), '$3'}.
atom -> 'fulfillment' 'in' '(' idents ')' : {fulfillment, '$4'}.
atom -> 'time' clock '..' clock : {time, located('$2'), located('$4')}.
atom -> 'weekday' 'in' '(' idents ')' : {weekday, '$4'}.

amount -> '$empty' : 1.
amount -> times : value('$1').
amount -> 'x' int : value('$2').

effects -> effect : ['$1'].
effects -> effect effects : ['$1' | '$2'].
effects -> effect ',' effects : ['$1' | '$3'].

effect -> 'discount' int '%' target cap : {percent, located('$2'), '$4', '$5'}.
effect -> 'discount' sum 'rub' target : {amount, '$2', '$4'}.
effect -> 'gift' string amount : {gift, located('$2'), '$3'}.
effect -> 'price' string sum : {price, located('$2'), element(1, '$3')}.

target -> '$empty' : cart.
target -> 'on' string : {products, [located('$2')]}.
target -> 'on' '(' strings ')' : {products, '$3'}.

cap -> '$empty' : nil.
cap -> 'max' sum : '$2'.

sum -> int : {value('$1') * 100, element(2, '$1')}.
sum -> money : located('$1').

strings -> string : [located('$1')].
strings -> string ',' strings : [located('$1') | '$3'].

idents -> ident : [located('$1')].
idents -> ident ',' idents : [located('$1') | '$3'].

Erlang code.

value({_, _, Value}) -> Value.

located({_, Loc, Value}) -> {Value, Loc}.
