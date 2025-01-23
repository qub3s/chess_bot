## Setup
Fedora:
dnf install flexiblas flexiblas-devel
switch to serial -> flexiblas default OPEN-BLAS-SERIAL 

Compile always with -Doptimize=ReleaseFast


## DONE
- Write Board visualization
- Write CPU NN (Adams, Linear Layer, ReLU, MSE)
- Write basic chess rules, still missing:
    - checking
    - draw at move or positional 
    - draw at 50 move no pawn move
    - castling
    - en passant
    - promoting other than to queen 

## TODO:
- Implement checking and 50 move rule
- Implement multi-threading during training (play multiple games in parallel)
- Implement a learning technique that shows an improvement and convincingly beats random initialization
- Implement search with Alpha-Beta
- Train strong NN
- Implement multi-threading during evaluation (parallelised alpha beta pruning)


Approach:
- Create an Pool randomly generated agents and have them compete against each other
- If the winrate of an agents drops beneath a certain threshhold, remove the agent and replace it with an copy of the best performing agent
