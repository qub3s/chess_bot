#include <immintrin.h>
#include <stdio.h> 
#include <time.h> 
#include <flexiblas/cblas.h>
#include <math.h>
#include <stdbool.h>

void naive_algo(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    for( int i = 0; i < rows; i++){
        res[i] = vec_add[i];
        for( int j = 0; j < cols; j++){
            res[i] += vec_mul[j] * matrix[i * cols + j];
        }
    }
    return;
}

void trans_naive_algo(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    for( int i = 0; i < cols; i++){
        res[i] = vec_add[i];
        for( int j = 0; j < rows; j++){
            res[i] += vec_mul[j] * matrix[j * cols + i];
        }
    }
    return;
}

// function has to be compiled with -O3 flag
void trans_mat_vec_AVX2(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    if( cols%8 != 0 || rows%8 != 0){
        return trans_naive_algo(cols, rows, matrix, vec_add, vec_mul, res);
    }

    __m256 v_mat, v_vec, v_res, store;

    for( int i = 0; i < cols; i += 8){
        store = _mm256_loadu_ps(vec_add+i);
        _mm256_storeu_ps(res+i, store);   
    }

    for( int i = 0; i < rows; i += 1){
        v_vec = _mm256_set1_ps(vec_mul[i]);

        for(int j = 0; j < cols; j += 8){
            v_mat = _mm256_loadu_ps(matrix + cols * i + j);
            v_res = _mm256_loadu_ps(res+j);

            store = _mm256_fmadd_ps(v_mat, v_vec, v_res); 

            _mm256_storeu_ps(res+j, store);   
        }
    }
}

// https://github.com/srinathv/ImproveHpc/blob/master/intel/2015-compilerSamples/C%2B%2B/intrinsic_samples/intrin_dot_sample.c
void mat_vec_AVX2(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    if( cols%8 != 0 || rows%8 != 0){
        return naive_algo(cols, rows, matrix, vec_add, vec_mul, res);
    }

    __m256 v_mat, v_vec, sum;
    __m128 top,bot;

    for( int i = 0; i < rows; i++){
        sum = _mm256_setzero_ps();  

        for(int j = 0; j < cols; j += 8){
            v_vec = _mm256_loadu_ps(vec_mul + j);  // versuchen aus dem inneren loop rauszubewegen
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
        ptr[h] = h /3.1415;
    }
}

int check_same(int len, float *ptr_a, float *ptr_b){
    for(int x = 0; x < len; x++){
        if(ptr_a[x] != ptr_b[x]){
            return 0;
        }
    }
    return 1;
}

void print_bool(int x){
    if(x == 1){
        printf("True\n");
    }
    else{
        printf("False\n");
    }
}

//void matrix_test(int scale_cols, int scale_rows){
//    int cols = 8 * scale_cols;
//    int rows = 8 * scale_rows;
//
//    clock_t time;
//
//    float *vec_mul; 
//    vec_mul = malloc(cols * sizeof(float)); 
//
//    float *vec_add; 
//    vec_add = malloc(rows * sizeof(float));
//
//    float *matrix;
//    matrix= malloc(rows * cols * sizeof(float));
//
//    float res_blas[rows];
//    float res_avx[rows];
//    float res_naive[rows];
//
//    // set values
//    reset_values(vec_mul, cols);
//    reset_values(vec_add, rows);
//    reset_values(matrix, rows*cols);
//
//    time = clock();
//    cblas_sgemv(CblasRowMajor, CblasNoTrans, rows, cols, 1, matrix, cols, vec_mul, 1, 1, vec_add, 1 ); 
//    time = clock() - time;
//    printf("%f\n", (float)time/CLOCKS_PER_SEC);
//
//    for(int x = 0; x < rows; x++){
//        res_blas[x] = vec_add[x];
//    }
//    print(res_blas, rows, 1);
//
//    // reset_values
//    reset_values(vec_mul, cols);
//    reset_values(vec_add, rows);
//    reset_values(matrix, rows*cols);
//
//    time = clock();
//    mat_vec_AVX2(cols, rows, matrix, vec_add, vec_mul, res_avx); 
//    time = clock() - time;
//    printf("%f\n", (float)time/CLOCKS_PER_SEC);
//
//    print(res_avx, rows, 1);
//
//    time = clock();
//    naive_algo(cols, rows, matrix, vec_add, vec_mul, res_naive); 
//    time = clock() - time;
//    printf("%f\n", (float)time/CLOCKS_PER_SEC);
//
//    print(res_naive, rows, 1);
//}

//void trans_matrix_test(int scale_cols, int scale_rows){
//    int cols = 8 * scale_cols;
//    int rows = 8 * scale_rows;
//
//    clock_t time;
//
//    float *vec_mul; 
//    vec_mul = malloc(rows * sizeof(float)); 
//
//    float *vec_add; 
//    vec_add = malloc(cols * sizeof(float));
//
//    float *matrix;
//    matrix= malloc(rows * cols * sizeof(float));
//
//    float res_blas[cols];
//    float res_avx[cols];
//    float res_naive[cols];
//
//    reset_values(vec_mul, rows);
//    reset_values(vec_add, cols);
//    reset_values(matrix, rows*cols);
//
//    time = clock();
//    cblas_sgemv(CblasRowMajor, CblasTrans, rows, cols, 1, matrix, cols, vec_mul, 1, 1, vec_add, 1 ); 
//    time = clock() - time;
//    printf("%f\n", (float)time/CLOCKS_PER_SEC);
//
//    for(int x = 0; x < cols; x++){
//        res_blas[x] = vec_add[x];
//    }
//    print(res_blas, cols, 1);
//
//    reset_values(vec_mul, rows);
//    reset_values(vec_add, cols);
//    reset_values(matrix, rows*cols);
//
//    time = clock();
//    trans_mat_vec_AVX2(cols, rows, matrix, vec_add, vec_mul, res_avx); 
//    time = clock() - time;
//    printf("%f\n", (float)time/CLOCKS_PER_SEC);
//
//    print(res_avx, cols, 1);
//
//    time = clock();
//    trans_naive_algo(cols, rows, matrix, vec_add, vec_mul, res_naive); 
//    time = clock() - time;
//    printf("%f\n", (float)time/CLOCKS_PER_SEC);
//
//    print(res_naive, cols, 1);
//}



//int main() {
//    printf("compiled...\n");
//
//    //matrix_test(1,2);
//    trans_matrix_test(2,1);
//
//}
