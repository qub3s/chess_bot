#include "stdio.h"
#include "stdlib.h"
#include "flexiblas/cblas.h"
#define N 5000

double A[N][N], B[N][N], C[N][N];

int main(){

    for(int i=0; i<N; i++)
      for(int j=0; j<N; j++){
          A[i][j]=rand(); B[i][j]=rand(); C[i][j]=0;
      }

    cblas_dgemm(CblasRowMajor,CblasNoTrans,CblasNoTrans, N,N,N, 1, \
                &A[0][0],N, &B[0][0],N, 0,&C[0][0],N);
}
