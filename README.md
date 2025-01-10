## Setup
Fedora:
dnf install flexiblas flexiblas-devel
switch to serial -> flexiblas default OPEN-BLAS-SERIAL 


## DONE
- Write Board visualization
- Write CPU NN (Adams, Linear Layer, ReLU, MSE)
- Write basic chess rules, still missing:
    - draw at move or positional 
    - draw at 50 move no pawn move
    - castling
    - en passant
    - promoting other than to queen 

## TODO:
- Implement multi-threading during training (play multiple games in parallel)
- Implement a learning technique that shows an improvement and convincingly beats random initialization
- Implement search with Alpha-Beta
- Train strong NN
- Implement multi-threading during evaluation (parallelised alpha beta pruning)
