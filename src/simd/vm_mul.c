#include <immintrin.h>
#include <stdio.h>
#include <stdbool.h>

// https://github.com/srinathv/ImproveHpc/blob/master/intel/2015-compilerSamples/C%2B%2B/intrinsic_samples/intrin_dot_sample.c
bool mat_vec_AVX_2(int cols, int rows, float *matrix, float *vec, float *res){
    if( cols%8 != 0 || rows%8 != 0 ){
        return false;
    }

    for( int i = 0; i < cols; i++){
        __m256 v_mat, v_vec, sum;
        __m128 top,bot;
        sum = _mm256_setzero_ps();  

        for(int j = 0; j < rows; j += 8){
            v_mat= _mm256_loadu_ps(matrix + cols * i + j);   
            v_vec = _mm256_loadu_ps(vec + j);  
            sum = _mm256_fmadd_ps(v_mat, v_vec, sum); 
        }

        sum = _mm256_hadd_ps(sum, sum); 

        top = _mm256_extractf128_ps(sum,1);   
        bot = _mm256_extractf128_ps(sum,0);  

        top = _mm_add_ps(top,bot);    
        top = _mm_hadd_ps(top,top);  

        _mm_store_ss(res+i,top);
    }

    return true;
}


// Fill the arrays
int main() {
    printf("compiled...\n");

    float vec[8] = {};
    float matrix[8*8] = {};
    float res[8] = {};

    for(int x = 0; x < 8; x++){
        vec[x] = x;
    }

    for(int x = 0; x < 64; x++){
        matrix[x] = x;
    }

    mat_vec_AVX_2(8, 8, matrix, vec, res); 

    for(int x = 0; x < 8; x++){
        printf("%f \n", res[x]);
    }
    printf("\n");

}
