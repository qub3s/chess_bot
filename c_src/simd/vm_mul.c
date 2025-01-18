#include <immintrin.h>
#include <stdio.h> 
#include <time.h> 
#include <flexiblas/cblas.h>

void naive_algo(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    for( int i = 0; i < rows; i++){
        for( int j = 0; j < cols; j++){
        }
        res[i] += vec_add[i];
    }
    return;
}

// https://github.com/srinathv/ImproveHpc/blob/master/intel/2015-compilerSamples/C%2B%2B/intrinsic_samples/intrin_dot_sample.c
void mat_vec_AVX2(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    if( cols%8 != 0 || rows%8 != 0){
        printf("Dimensions not allowed: %d - %d\n", cols, rows);
        return ;
    }

    __m256 v_mat, v_vec, sum;
    __m128 top,bot;

    for( int i = 0; i < rows; i++){
        sum = _mm256_setzero_ps();  

        for(int j = 0; j < cols; j += 8){
            v_vec = _mm256_loadu_ps(vec_mul + j);  
            v_mat = _mm256_loadu_ps(matrix + cols * i + j);   
            sum = _mm256_fmadd_ps(v_mat, v_vec, sum); 
        }

        sum = _mm256_hadd_ps(sum, sum); 

        top = _mm256_extractf128_ps(sum,1);   
        bot = _mm256_extractf128_ps(sum,0);  

        top = _mm_add_ps(top,bot);    
        top = _mm_hadd_ps(top,top);  

        _mm_store_ss(res+i,top);
        res[i] += vec_add[i];
    }

    return;
}

void print(float *ptr, int width, int height){
    printf("\n");

    for(int h = 0; h < height; h++){
        for(int w = 0; w < width; w++){
            printf("%f  ", ptr[h*width+w]);
        }
        printf("\n");
    }

    printf("\n");
}

void reset_values(float *ptr,int values){
    for(int h = 0; h < values; h++){
        ptr[h] = (float) (h%7);
    }
}


// Fill the arrays
//int main() {
//    printf("compiled...\n");
//    int s1 = 8;
//    int s2 = 16;
//
//    float *vec_mul; 
//    float *vec_add; 
//    vec_mul = malloc(cols * sizeof(float)); 
//    vec_add = malloc(rows * sizeof(float));
//
//    float *matrix;
//    matrix = malloc(rows * cols * sizeof(float));
//    float res[rows] = {};
//
//    // set values
//    reset_values(vec_mul, cols);
//    reset_values(vec_add, rows);
//    reset_values(matrix, rows*cols);
//
//    clock_t t;
//    double time_taken;
//
//    t = clock(); 
//    cblas_sgemv(CblasColMajor, CblasTrans, cols, rows, 1, matrix, cols, vec_mul, 1, 1, vec_add, 1 ); 
//    t = clock() - t; 
//    time_taken = ((double)t)/CLOCKS_PER_SEC; // in seconds 
//    //printf("BLAS:  %f \n", time_taken);
//
//    print(vec_add, 1, rows);
//
//    // reset_values
//    reset_values(vec_mul, cols);
//    reset_values(vec_add, rows);
//    reset_values(matrix, rows*cols);
//
//    t = clock(); 
//    mat_vec_AVX2(cols, rows, matrix, vec_add, vec_mul, res); 
//    t = clock() - t; 
//    time_taken = ((double)t)/CLOCKS_PER_SEC; // in seconds 
//    printf("AVX2:  %f \n", time_taken);
//
//    print(res, 1, rows);
//
//    for(int i = 0; i < rows; i++){
//        res[i] = 0;
//    }
//
//    // reset_values
//    reset_values(vec_mul, cols);
//    reset_values(vec_add, rows);
//    reset_values(matrix, cols*rows);
//
//    naive_algo(cols, rows, matrix, vec_add, vec_mul, res);
//
//    print(res, 1, rows);
//    //// reset_values
//    //reset_values(vec_mul, s1);
//    //reset_values(vec_add, s1);
//    //reset_values(matrix, s1*s2);
//
//    //t = clock(); 
//    //naive_algo(s1, s2, matrix, vec_mul, vec_add, res);
//    //t = clock() - t; 
//    //time_taken = ((double)t)/CLOCKS_PER_SEC; // in seconds 
//    //printf("Naive: %f \n", time_taken);
//
//    //print(res, 1, s1);
//}
