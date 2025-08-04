
#include <stdio.h>
#include <sys/stat.h>
#include <string>
#include <time.h>
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


int is_end_of_file(FILE *file) {
    struct stat file_stat;
    
    // 获取文件的状态信息
    if (fstat(fileno(file), &file_stat) != 0) {
        perror("fstat error");
        return -1;
    }

    long current_pos = ftell(file);  // 获取当前文件指针位置
    return current_pos == file_stat.st_size;  // 如果文件指针位置等于文件大小，表示已到达文件末尾
}


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
    if (argc != 5) 
    {
        printf("usage: %s infile outfile parallelism debug\n parallelism:total SM num\n", argv[0]);
        exit(1);
    }
    int parallelism=std::stoi(argv[3]);
    int debug_=std::stoi(argv[4]);
    int threads_perSM=128;
    FILE *fin=fopen(argv[1],"rb"),*fout=fopen(argv[2],"wb");
    unsigned char*reading_buf_cpu[parallelism],*writing_buf_cpu[parallelism],*reading_buf_gpu[parallelism],*writing_buf_gpu[parallelism];
    unsigned char* codelen_gpu[parallelism];
    unsigned long long* code_gpu[parallelism];
    for(int i=0;i<parallelism;i++){
        reading_buf_cpu[i]=(unsigned char*)malloc(65536*256+65536);
        writing_buf_cpu[i]=(unsigned char*)malloc(65536*256*8+65536);
        cudaMalloc((void **)&reading_buf_gpu[i], 65536*256+65536);
        cudaMalloc((void **)&writing_buf_gpu[i], 65536*256*8+65536);
        cudaMalloc((void **)&codelen_gpu[i], 256);
        cudaMalloc((void **)&code_gpu[i], 256*8);
    }
    long sum_time=0;
    while(!is_end_of_file(fin)){
        int rawsize[parallelism];
        int yuanshi_meikuai[parallelism];
        int cnt=0;
        int numthreads[parallelism];
        for(int iii=0;iii<parallelism;iii++){
            //long current_pos = 
            if(debug_)
            printf("cur_pos:%lld\n",ftell(fin));
            if(is_end_of_file(fin))break;
            cnt++;
            fread(reading_buf_cpu[iii],1,4+17,fin);
            int pos=4+17;
            rawsize[iii]=huanyuan(reading_buf_cpu[iii])*256+reading_buf_cpu[iii][3];
            if(debug_)
            printf("rawsize=%d\n",rawsize[iii]);
            //int sum=reading_buf_cpu[4+17+3];
            //fread(reading_buf_cpu+4+17+3+1,1,sum*4-1,fin);
            unsigned char codelen[256];
            unsigned long long code[256];
            unsigned char*codecount=reading_buf_cpu[iii]+4+8+1;
            int i = 0;
            //int pos=4+17+3+1+sum*4-1;
            int sum_fuhao=0;
            //int textsize=huanyuan(&reading_buf_cpu[4+17+3+1+3*(sum-1)+1])+reading_buf_cpu[pos-1];
            //int yuanshi_meikuai=huanyuan(&reading_buf_cpu[4+17]);
            for(int k=0;k<8;k++) {
                sum_fuhao+=codecount[k]*(k+1);
            }
            fread(reading_buf_cpu[iii]+pos,1,sum_fuhao,fin);
            for(int kk=0;kk<8;kk++) {
                int k=(kk+1)%8;
                for(int j=0;j<codecount[k];j++){
                    codelen[i]=k+1;
                    memcpy(code+i,reading_buf_cpu[iii]+pos,k+1);
                    pos+=k+1;
                    i++;
                }
            }
            fread(reading_buf_cpu[iii]+pos,1,4,fin);
            yuanshi_meikuai[iii]=huanyuan(reading_buf_cpu[iii]+pos);
            numthreads[iii]=reading_buf_cpu[iii][pos+3];
            int gpu_start_pos=pos+3;
            pos+=4;
            fread(reading_buf_cpu[iii]+pos,1,numthreads[iii]*4-1,fin);
            int textsize=huanyuan(&reading_buf_cpu[iii][pos+3*(numthreads[iii]-1)]);//+reading_buf_cpu[iii][pos+numthreads[iii]*4-1-1]
            
            if(debug_)
            printf("yasuosize=%d\n",textsize);
            pos+=numthreads[iii]*4-1;
            //assert()
            fread(reading_buf_cpu[iii]+pos,1,textsize,fin);
            //reading_buf_gpu,*writing_buf_gpu
            cudaMemcpy(reading_buf_gpu[iii],reading_buf_cpu[iii]+gpu_start_pos,1+4*numthreads[iii]-1+textsize,cudaMemcpyHostToDevice);
            //CHECK(cudaGetLastError());
            //CHECK(cudaDeviceSynchronize());
            cudaMemcpy(code_gpu[iii],code,256*8,cudaMemcpyHostToDevice);
            cudaMemcpy(codelen_gpu[iii],codelen,256,cudaMemcpyHostToDevice);
            //CHECK(cudaGetLastError());
            //CHECK(cudaDeviceSynchronize());
            if(debug_)
            printf("numthreads[iii]=%d\n",numthreads[iii]);

        }
        CHECK(cudaGetLastError());
        CHECK(cudaDeviceSynchronize());
        long time0=clock();
        for(int iii=0;iii<cnt;iii++){

            decode<<<1,numthreads[iii]>>>(reading_buf_gpu[iii],writing_buf_gpu[iii],code_gpu[iii],codelen_gpu[iii],yuanshi_meikuai[iii]);
            if(debug_)
                printf("time=%lld\n",clock());
        }
        CHECK(cudaGetLastError());
        CHECK(cudaDeviceSynchronize());
            if(debug_)
                printf("finish_time=%lld\n",clock());
        sum_time+=clock()-time0;
        for(int iii=0;iii<cnt;iii++){
            cudaMemcpy(writing_buf_cpu[iii],writing_buf_gpu[iii],rawsize[iii],cudaMemcpyDeviceToHost);
            fwrite(writing_buf_cpu[iii],1,rawsize[iii],fout);
        }
    }
    printf("sum_time=%lld\n",sum_time);
    fclose(fin);
    fclose(fout);
    for(int i=0;i<parallelism;i++){
        free(reading_buf_cpu[i]);
        free(writing_buf_cpu[i]);
        cudaFree((void **)&reading_buf_gpu[i]);
        cudaFree((void **)&writing_buf_gpu[i]);
        cudaFree((void **)&codelen_gpu[i]);
        cudaFree((void **)&code_gpu[i]);
    }
    return 0;
}