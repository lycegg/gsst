
#include <stdio.h>
//#include <iostream>
//#include <fstream>
#define SIZE_START 0
#define VER_START 4
#define ZER_START 4+8
#define LEN_START 4+8+1
#define FUHAO_START 4+8+1+8

#define CHECK(call)                                   \
do                                                    \
{                                                     \
    const cudaError_t error_code = call;              \
    if (error_code != cudaSuccess)                    \
    {                                                 \
        printf("CUDA Error:\n");                      \
        printf("    File:       %s\n", __FILE__);     \
        printf("    Line:       %d\n", __LINE__);     \
        printf("    Error code: %d\n", error_code);   \
        printf("    Error text: %s\n",                \
            cudaGetErrorString(error_code));          \
        exit(1);                                      \
    }                                                 \
} while (0)



void __global__ decode(unsigned char*reading,unsigned char*writing,unsigned long long* code_table,unsigned char* codelen,int yuanshi){
    const int n = blockDim.x * blockIdx.x + threadIdx.x;
    int start=0;
    int sum=reading[0];
    if(n!=0)start=reading[n*3]+reading[n*3-1]*256+reading[n*3-2]*65536;
    int end=reading[n*3+3]+reading[n*3+2]*256+reading[n*3+1]*65536;
    writing+=yuanshi*n;
    if(n!=0)writing+=reading[3*sum+n];
    reading+=4*sum;
    for(int i=start;i<end;i++){
        if(reading[i]!=255){
            memcpy(writing,&(code_table[reading[i]]),codelen[reading[i]]);
            writing+=codelen[reading[i]];
        }
        else{
            i++;
            *writing=reading[i];
            writing++;
        }
    }
    //printf("from%dto%d\n",start,end);
}
int huanyuan(unsigned char*x){
    return x[0]*65536+x[1]*256+x[2];
}
int main(int argc, char **argv){
    if (argc != 3) 
    {
        printf("usage: %s infile outfile\n", argv[0]);
        exit(1);
    }
    FILE *fin=fopen(argv[1],"rb"),*fout=fopen(argv[2],"wb");
    int rawsize;
    unsigned char*reading_buf_cpu,*writing_buf_cpu,*reading_buf_gpu,*writing_buf_gpu;
    reading_buf_cpu=(unsigned char*)malloc(65536*256+65536);

    fread(reading_buf_cpu,1,4+17,fin);
    int pos=4+17;
    rawsize=huanyuan(reading_buf_cpu)*256+reading_buf_cpu[3];
    //int sum=reading_buf_cpu[4+17+3];
    //fread(reading_buf_cpu+4+17+3+1,1,sum*4-1,fin);
    unsigned char codelen[256];
    unsigned long long code[256];
    unsigned char*codecount=reading_buf_cpu+4+8+1;
    int i = 0;
    //int pos=4+17+3+1+sum*4-1;
    int sum_fuhao=0;
    //int textsize=huanyuan(&reading_buf_cpu[4+17+3+1+3*(sum-1)+1])+reading_buf_cpu[pos-1];
    //int yuanshi_meikuai=huanyuan(&reading_buf_cpu[4+17]);
    for(int k=0;k<8;k++) {
        sum_fuhao+=codecount[k]*(k+1);
    }
    fread(reading_buf_cpu+pos,1,sum_fuhao,fin);
    for(int kk=0;kk<8;kk++) {
        int k=(kk+1)%8;
        for(int j=0;j<codecount[k];j++){
            codelen[i]=k+1;
            memcpy(code+i,reading_buf_cpu+pos,k+1);
            pos+=k+1;
            i++;
        }
    }
    fread(reading_buf_cpu+pos,1,4,fin);
    int yuanshi_meikuai=huanyuan(reading_buf_cpu+pos);
    int sum=reading_buf_cpu[pos+3];
    int gpu_start_pos=pos+3;
    pos+=4;
    fread(reading_buf_cpu+pos,1,sum*4-1,fin);
    int textsize=huanyuan(&reading_buf_cpu[pos+3*(sum-1)+1])+reading_buf_cpu[pos+sum*4-1-1];
    pos+=sum*4-1;
    //assert()
    fread(reading_buf_cpu+pos,1,textsize,fin);
    //reading_buf_gpu,*writing_buf_gpu
    cudaMalloc((void **)&reading_buf_gpu, 65536*256+65536);
    cudaMalloc((void **)&writing_buf_gpu, rawsize+65536);
    cudaMemcpy(reading_buf_gpu,reading_buf_cpu+gpu_start_pos,1+4*sum-1+textsize,cudaMemcpyHostToDevice);
    //CHECK(cudaGetLastError());
    //CHECK(cudaDeviceSynchronize());
    unsigned char* codelen_gpu;
    unsigned long long* code_gpu;
    cudaMalloc((void **)&codelen_gpu, 256);
    cudaMalloc((void **)&code_gpu, 256*8);
    cudaMemcpy(code_gpu,code,256*8,cudaMemcpyHostToDevice);
    cudaMemcpy(codelen_gpu,codelen,256,cudaMemcpyHostToDevice);
    CHECK(cudaGetLastError());
    CHECK(cudaDeviceSynchronize());
    decode<<<1,sum>>>(reading_buf_gpu,writing_buf_gpu,code_gpu,codelen_gpu,yuanshi_meikuai);
    printf("sum=%d\n",sum);
    CHECK(cudaGetLastError());
    CHECK(cudaDeviceSynchronize());

    writing_buf_cpu=(unsigned char*)malloc(rawsize+65536);
    cudaMemcpy(writing_buf_cpu,writing_buf_gpu,rawsize,cudaMemcpyDeviceToHost);
    fwrite(writing_buf_cpu,1,rawsize,fout);
    fclose(fin);
    fclose(fout);
}