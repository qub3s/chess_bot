# Chess Bot
The aim of this project was it to develop a chess bot of resonable playing strenght. As the primary purpose of this project was furthering programming and Zig knowledge, no external packages were used (exept Raylib). This project can be divided in two parts move generation and move evaluation. <br>
<br>
One of the central pieces of a chess engine is the move generation. For efficient move generation this project implemented a slightly modified version of bitboards, the same method also used in Top chess engines (https://www.chessprogramming.org/Bitboards). For simplicity reasons some chess rules like en passant or castling when checked (or through checks) are not implemented. Furthermore the game is played until the king is actually captured. With these simplifications a single core move generation speed of more than 10Mnps was reached varing slightly between cpus. While this is still significantly slower than top chess engines, it is three orders of magnitude faster than the naive implementation (not using bitboards) that was first tried. <br>
<br>



<br>
<br>
Besides move generation and move evaluation chess engines like Stockfish use a variety of methods to prunde the search tree and increase the search speed. This project only uses Alpha-Beta Pruning to a fixed depth. 


## Setup
- devel packages for raylib needed
- Execute: zig build --summary all -Doptimize=ReleaseFast && time ./zig-out/bin/exe

## DONE
- Write Board visualization
- Write CPU NN (Adams, Linear Layer, ReLU, MSE)
- Implement 50 move rule
- Write basic chess rules, still missing:
    - draw positional repetition 
    - castling
    - en passant
    - promoting other than to queen 
- Implement multi-threading during training (play multiple games in parallel)


## TODO:
- Implement a learning technique that shows an improvement and convincingly beats random initialization
- Implement search with Alpha-Beta
- Train strong NN
- Implement multi-threading during evaluation (parallelised alpha beta pruning)
