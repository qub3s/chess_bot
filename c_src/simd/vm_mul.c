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
            res[i] += vec_mul[j] * matrix[j + i * rows];
        }
    }
    return;
}

void trans_naive_algo(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    for( int i = 0; i < cols; i++){
        res[i] = vec_add[i];
        for( int j = 0; j < rows; j++){
            res[i] += vec_mul[j] * matrix[i * rows + j];
        }
    }
    return;
}

// function has to be compiled with -O3 flag
void trans_mat_vec_AVX2(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    if( cols%8 != 0 || rows%8 != 0){
        printf("overflow\n");
        return trans_naive_algo(cols, rows, matrix, vec_add, vec_mul, res);
    }

    __m256 v_mat, v_vec, v_res, store;

    for( int i = 0; i < rows; i += 1){
        v_vec = _mm256_set1_ps(vec_mul[i]);

        for(int j = 0; j < cols; j += 8){
            v_mat = _mm256_loadu_ps(matrix + cols * i + j);
            v_res = _mm256_loadu_ps(res+j);

            store = _mm256_fmadd_ps(v_mat, v_vec, v_res); 

            _mm256_storeu_ps(res+j, store);   
        }
    }

    for( int i = 0; i < rows; i += 8){
        v_res = _mm256_loadu_ps(res+i);
        v_vec = _mm256_loadu_ps(vec_add+i);
        store = _mm256_add_ps(v_vec, v_res);
        _mm256_storeu_ps(res+i, store);   
    }
}

// https://github.com/srinathv/ImproveHpc/blob/master/intel/2015-compilerSamples/C%2B%2B/intrinsic_samples/intrin_dot_sample.c
void mat_vec_AVX2(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    if( cols%8 != 0 || rows%8 != 0){
        printf("overflow\n");
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

// Fill the arrays
int main() {
    printf("compiled...\n");
    int rows = 8000;
    int cols = 8000;
    int max; 
    clock_t time;

    if( rows > cols ){ max = rows; } else{ max = cols; }

    float *vec_mul; 
    float *vec_add; 
    vec_mul = malloc(cols * sizeof(float)); 
    vec_add = malloc(rows * sizeof(float));

    float *matrix;
    matrix= malloc(rows * cols * sizeof(float));

    float res_blas[rows];
    float res_avx[cols];
    float res_naive[rows];

    // set values
    reset_values(vec_mul, cols);
    reset_values(vec_add, rows);
    reset_values(matrix, rows*cols);

    time = clock();
    cblas_sgemv(CblasRowMajor, CblasTrans, rows, cols, 1, matrix, cols, vec_mul, 1, 1, vec_add, 1 ); 
    time = clock() - time;
    printf("%f\n", (float)time/CLOCKS_PER_SEC);

    for(int x = 0; x < rows; x++){
        res_blas[x] = vec_add[x];
    }

    //print(res_blas, rows, 1);

    // reset_values
    reset_values(vec_mul, cols);
    reset_values(vec_add, rows);
    reset_values(matrix, rows*cols);

    for(int x = 0; x < rows; x++){
        res_avx[x] = res_avx[x];
    }

    time = clock();
    trans_mat_vec_AVX2(cols, rows, matrix, vec_add, vec_mul, res_avx); 
    time = clock() - time;
    printf("%f\n", (float)time/CLOCKS_PER_SEC);

    //print(res_avx, rows, 1);

    time = clock();
    mat_vec_AVX2(cols, rows, matrix, vec_add, vec_mul, res_avx); 
    time = clock() - time;
    printf("%f\n", (float)time/CLOCKS_PER_SEC);

    //// reset_values
    //reset_values(vec_mul, cols);
    //reset_values(vec_add, rows);
    //reset_values(matrix, cols*rows);

    //trans_naive_algo(cols, rows, matrix, vec_add, vec_mul, res_naive);

    //print(res_naive, rows, 1);
}
