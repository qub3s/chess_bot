#include <immintrin.h>
#include <stdio.h>
#include <stdbool.h>
#include <time.h> 
#include <flexiblas/cblas.h>

// https://github.com/srinathv/ImproveHpc/blob/master/intel/2015-compilerSamples/C%2B%2B/intrinsic_samples/intrin_dot_sample.c
bool mat_vec_AVX2(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    if( cols%8 != 0 || rows%8 != 0 ){
        printf("break");
        return false;
    }

    float result;
    for( int i = 0; i < cols; i++){

        __m256 v_mat, v_vec, sum;
        __m128 top,bot;
        sum = _mm256_setzero_ps();  
        v_vec = _mm256_loadu_ps(vec_mul + i);  

        for(int j = 0; j < rows; j += 8){
            v_mat = _mm256_loadu_ps(matrix + cols * j + i);   

            sum = _mm256_fmadd_ps(v_mat, v_vec, sum); 
            sum = _mm256_hadd_ps(sum, sum); 

            top = _mm256_extractf128_ps(sum,1);   
            bot = _mm256_extractf128_ps(sum,0);  

            top = _mm_add_ps(top,bot);    
            top = _mm_hadd_ps(top,top);  
            _mm_store_ss(&result,top);
            printf("%f   ", result);


            res[j] += result;
        }

        res[i] += vec_add[i];
    }

    return true;
}

//bool s_mat_vec_AVX2(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
//    if( cols%8 != 0 || rows%8 != 0 ){
//        printf("break");
//        return false;
//    }
//
//    __m256 v_mat, v_vec, sum;
//    __m128 top,bot;
//    sum = _mm256_setzero_ps();  
//
//    for( int i = 0; i < cols; i++){
//        v_vec = _mm256_loadu_ps();  
//        for(int j = 0; j < rows; j += 8){
//            v_mat = _mm256_loadu_ps();   
//            sum = _mm256_fmadd_ps(v_mat, v_vec, sum); 
//        }
//
//        sum = _mm256_hadd_ps(sum, sum); 
//
//        top = _mm256_extractf128_ps(sum,1);   
//        bot = _mm256_extractf128_ps(sum,0);  
//
//        top = _mm_add_ps(top,bot);    
//        top = _mm_hadd_ps(top,top);  
//
//        _mm_store_ss(res+i,top);
//        res[i] += vec_add[i];
//    }
//
//    return true;
//}

bool naive_algo(int cols, int rows, float *matrix, float *vec_add, float *vec_mul, float *res){
    if( cols%8 != 0 || rows%8 != 0 ){
        printf("break");
        return false;
    }

    for( int i = 0; i < cols; i++){
        for( int j = 0; j < rows; j++){
            res[i] += vec_mul[j] * matrix[j + i * rows];
        }
        res[i] += vec_add[i];
    }
    return true;
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
        ptr[h] = (float) (h%3);
    }
}


// Fill the arrays
int main() {
    printf("compiled...\n");

    int s = 8;

    float *vec_mul;
    float *vec_add;
    vec_mul = malloc(s * sizeof(float));
    vec_add = malloc(s * sizeof(float));
    float *matrix;
    matrix = malloc(s*s * sizeof(float));
    float res[s] = {};

    // set values
    reset_values(vec_mul, s);
    //reset_values(vec_add, s);
    reset_values(matrix, s*s);

    clock_t t;
    double time_taken;

    t = clock(); 

    cblas_sgemv(CblasColMajor, CblasTrans, s, s, 1, matrix, s, vec_mul, 1, 1, vec_add, 1 ); 
    t = clock() - t; 
    time_taken = ((double)t)/CLOCKS_PER_SEC; // in seconds 
    printf("BLAS:  %f \n", time_taken);

    //print(vec_add, 1, s);

    // reset_values
    reset_values(vec_mul, s);
    reset_values(vec_add, s);
    reset_values(matrix, s*s);

    t = clock(); 
    mat_vec_AVX2(s, s, matrix, vec_mul, vec_add, res); 
    t = clock() - t; 
    time_taken = ((double)t)/CLOCKS_PER_SEC; // in seconds 
    printf("AVX2:  %f \n", time_taken);

    print(res, 1, s);
    for(int i = 0; i < s; i++){
        res[i] = 0;
    }

    // reset_values
    reset_values(vec_mul, s);
    reset_values(vec_add, s);
    reset_values(matrix, s*s);

    t = clock(); 
    naive_algo(s, s, matrix, vec_mul, vec_add, res);
    t = clock() - t; 
    time_taken = ((double)t)/CLOCKS_PER_SEC; // in seconds 
    printf("Naive: %f \n", time_taken);

    print(res, 1, s);
}
