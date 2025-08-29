
#include <stdio.h>
#include <sys/stat.h>
#include <string>
#include <time.h>
#include <vector>
//#include <iostream>
//#include <fstream>
//#define SIZE_START 0
//#define VER_START 4
///#define ZER_START 4+8
//#define LEN_START 4+8+1
//#define FUHAO_START 4+8+1+8
using namespace std;
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
typedef pair<unsigned char*,int> ppi;

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


void __global__ decode(unsigned char**preading,unsigned char**pwriting,unsigned long long** pcode_table,unsigned char** pcodelen,int *p_RawPerThread){
    unsigned char* reading=preading[blockIdx.x];
    unsigned char*writing=pwriting[blockIdx.x];
    unsigned long long*code_table= pcode_table[blockIdx.x];
    unsigned char*codelen= pcodelen[blockIdx.x];
    int RawPerThread=p_RawPerThread[blockIdx.x];
    const int n = threadIdx.x;
    int start=0;
    int sum=reading[0];
    if(n!=0)start=reading[n*3]+reading[n*3-1]*256+reading[n*3-2]*65536;
    int end=reading[n*3+3]+reading[n*3+2]*256+reading[n*3+1]*65536;
    writing+=RawPerThread*n;
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
int DESERIALIZE(unsigned char*x){
    return x[0]*65536+x[1]*256+x[2];
}
vector<ppi> readed,to_write;
FILE *fin,*fout;
long whole_count=0;
int file_stat_size;
void myread(){
    if(whole_count>=file_stat_size)return;
    
    int size;
    fread(&size,4,1,fin);whole_count+=4;
    unsigned char*buf=(unsigned char*)malloc(size);
    whole_count+=size;
    fread(buf,1,size,fin);
    readed.push_back(ppi(buf,size));
}
int main(int argc, char **argv){
    if (argc != 6) 
    {
        printf("usage: %s infile outfile debug parallelismS parallelismT\nparallelismS:total SM num\nparallelismT:thread num per SM\n", argv[0]);
        exit(1);
    }
    int debug_=std::stoi(argv[3]);
    int parallelism=std::stoi(argv[4]);
    int threads_perSM=std::stoi(argv[5]);
    fin=fopen(argv[1],"rb");fout=fopen(argv[2],"wb");
    unsigned char*reading_buf_cpu[parallelism],*whole_reading_buf_gpu[2][parallelism],*whole_writing_buf_gpu[2][parallelism];//,*writing_buf_cpu[parallelism]
    unsigned char **whole_preading_buf_gpu[2],**whole_pwriting_buf_gpu[2];
    unsigned char* whole_codelen_gpu[2][parallelism];
    unsigned char** whole_pcodelen_gpu[2];
    unsigned long long* whole_code_gpu[2][parallelism];
    unsigned long long** whole_pcode_gpu[2];
    int*whole_p_RawPerThreadGpu[2];
    for(int i=0;i<parallelism;i++){
        //reading_buf_cpu[i]=(unsigned char*)malloc(65536*256+65536);
        //writing_buf_cpu[i]=(unsigned char*)malloc(65536*256*8+65536);
        cudaMalloc((void **)&whole_reading_buf_gpu[0][i], 65536*256+65536);
        cudaMalloc((void **)&whole_writing_buf_gpu[0][i], 4*1024*1025);
        cudaMalloc((void **)&whole_codelen_gpu[0][i], 256);
        cudaMalloc((void **)&whole_code_gpu[0][i], 256*8);
        cudaMalloc((void **)&whole_reading_buf_gpu[1][i], 65536*256+65536);
        cudaMalloc((void **)&whole_writing_buf_gpu[1][i], 4*1024*1025);
        cudaMalloc((void **)&whole_codelen_gpu[1][i], 256);
        cudaMalloc((void **)&whole_code_gpu[1][i], 256*8);
    }
        cudaMalloc((void **)&whole_p_RawPerThreadGpu[0], parallelism*sizeof(int));
        cudaMalloc((void **)&whole_preading_buf_gpu[0], parallelism*sizeof(int*));
        cudaMalloc((void **)&whole_pwriting_buf_gpu[0], parallelism*sizeof(int*));
        cudaMalloc((void **)&whole_pcodelen_gpu[0], parallelism*sizeof(int*));
        cudaMalloc((void **)&whole_pcode_gpu[0], parallelism*sizeof(int*));
        cudaMalloc((void **)&whole_p_RawPerThreadGpu[1], parallelism*sizeof(int));
        cudaMalloc((void **)&whole_preading_buf_gpu[1], parallelism*sizeof(int*));
        cudaMalloc((void **)&whole_pwriting_buf_gpu[1], parallelism*sizeof(int*));
        cudaMalloc((void **)&whole_pcodelen_gpu[1], parallelism*sizeof(int*));
        cudaMalloc((void **)&whole_pcode_gpu[1], parallelism*sizeof(int*));
    long sum_time=0;
    //long sum_time_mem=0;
    //cudaStream_t cuda_streams[2];
    struct stat file_stat;
    if (fstat(fileno(fin), &file_stat) != 0) {
        perror("fstat error");
        return -1;
    }
    file_stat_size=file_stat.st_size;
    //unsigned char* whole_reading_file=(unsigned char*)malloc(file_stat_size);
    //fread(whole_reading_file,1,file_stat_size,fin);
    int last_cnt=0;
    int rawsize[2][parallelism];
    int streamcnt=0;
    long time0=clock();
    long iotime=0;
        long time1=clock();
    for(int i=0;i<parallelism;i++)
        myread();
        iotime+=clock()-time1;
    int writeidx=0;
    for(int process_idx=0;process_idx<readed.size();process_idx+=parallelism){
        printf("round_start\n");
        int cur_s=streamcnt&1;
        auto reading_buf_gpu=whole_reading_buf_gpu[cur_s];
        auto writing_buf_gpu=whole_writing_buf_gpu[cur_s];
        auto codelen_gpu=whole_codelen_gpu[cur_s];
        auto code_gpu=whole_code_gpu[cur_s];
        auto p_RawPerThreadGpu=whole_p_RawPerThreadGpu[cur_s];
        auto preading_buf_gpu=whole_preading_buf_gpu[cur_s];
        auto pwriting_buf_gpu=whole_pwriting_buf_gpu[cur_s];
        auto pcodelen_gpu=whole_pcodelen_gpu[cur_s];
        auto pcode_gpu=whole_pcode_gpu[cur_s];
        int RawPerThread[parallelism];
        int cnt=0;
        int numthreads[parallelism];
        printf("clock=%lld\n",clock());
        for(int iii=0;iii<parallelism;iii++){
            //whole_count+=4;
            reading_buf_cpu[iii]=readed[process_idx+iii].first;
            //writing_buf_cpu[iii]=(unsigned char*)malloc(4*1024*1025);
            //long current_pos = 
            //if(debug_)
            //printf("cur_pos:%lld\n",ftell(fin));
            if(process_idx+iii>=readed.size())break;
            cnt++;
            //fread(reading_buf_cpu[iii],1,4+17,fin);
            //whole_count+=4+17;
            int pos=4+17;
            rawsize[cur_s][iii]=DESERIALIZE(reading_buf_cpu[iii])*256+reading_buf_cpu[iii][3];
            //if(debug_)
            //printf("rawsize=%d\n",readed[process_idx+iii].second);
            //int sum=reading_buf_cpu[4+17+3];
            //fread(reading_buf_cpu+4+17+3+1,1,sum*4-1,fin);
            unsigned char codelen[parallelism][256];
            unsigned long long code[parallelism][256];
            unsigned char*codecount=reading_buf_cpu[iii]+4+8+1;
            int i = 0;
            //int pos=4+17+3+1+sum*4-1;
            int sum_fuhao=0;
            //int textsize=DESERIALIZE(&reading_buf_cpu[4+17+3+1+3*(sum-1)+1])+reading_buf_cpu[pos-1];
            //int RawPerThread=DESERIALIZE(&reading_buf_cpu[4+17]);
            for(int k=0;k<8;k++) {
                sum_fuhao+=codecount[k]*(k+1);
            }
            //fread(reading_buf_cpu[iii]+pos,1,sum_fuhao,fin);
            //whole_count+=sum_fuhao;
            for(int kk=0;kk<8;kk++) {
                int k=(kk+1)%8;
                for(int j=0;j<codecount[k];j++){
                    codelen[iii][i]=k+1;
                    memcpy(code[iii]+i,reading_buf_cpu[iii]+pos,k+1);
                    pos+=k+1;
                    i++;
                }
            }
            //fread(reading_buf_cpu[iii]+pos,1,4,fin);
            //whole_count+=4;
            RawPerThread[iii]=DESERIALIZE(reading_buf_cpu[iii]+pos);
            numthreads[iii]=reading_buf_cpu[iii][pos+3];
            int gpu_start_pos=pos+3;
            pos+=4;
            //fread(reading_buf_cpu[iii]+pos,1,numthreads[iii]*4-1,fin);
            //whole_count+=numthreads[iii]*4-1;
            int textsize=DESERIALIZE(&reading_buf_cpu[iii][pos+3*(numthreads[iii]-1)]);//+reading_buf_cpu[iii][pos+numthreads[iii]*4-1-1]
            
            if(debug_)
            printf("yasuosize=%d\n",textsize);
            pos+=numthreads[iii]*4-1;
            //assert()
            //fread(reading_buf_cpu[iii]+pos,1,textsize,fin);
            //whole_count+=textsize;
            //reading_buf_gpu,*writing_buf_gpu
            //CHECK(cudaGetLastError());
            //CHECK(cudaDeviceSynchronize());
            //long time1=clock();
            cudaMemcpyAsync(reading_buf_gpu[iii],reading_buf_cpu[iii]+gpu_start_pos,1+4*numthreads[iii]-1+textsize,cudaMemcpyHostToDevice);
            //CHECK(cudaGetLastError());
            //CHECK(cudaDeviceSynchronize());
            cudaMemcpyAsync(code_gpu[iii],code[iii],256*8,cudaMemcpyHostToDevice);
            cudaMemcpyAsync(codelen_gpu[iii],codelen[iii],256,cudaMemcpyHostToDevice);
            //sum_time_mem+=clock()-time1;
            //CHECK(cudaGetLastError());
            //CHECK(cudaDeviceSynchronize());
            if(debug_)
            printf("numthreads[iii]=%d\n",numthreads[iii]);

        }
        printf("clock=%lld\n",clock());
        //long time1=clock();
        cudaMemcpyAsync(p_RawPerThreadGpu,RawPerThread,parallelism*sizeof(int),cudaMemcpyHostToDevice);
        //for(int iii=0;iii<cnt;iii++){
        cudaMemcpyAsync(preading_buf_gpu,reading_buf_gpu, parallelism*sizeof(int*),cudaMemcpyHostToDevice);
        cudaMemcpyAsync(pwriting_buf_gpu,writing_buf_gpu, parallelism*sizeof(int*),cudaMemcpyHostToDevice);
        cudaMemcpyAsync(pcodelen_gpu,codelen_gpu, parallelism*sizeof(int*),cudaMemcpyHostToDevice);
        cudaMemcpyAsync(pcode_gpu,code_gpu, parallelism*sizeof(int*),cudaMemcpyHostToDevice);
        printf("clock=%lld\n",clock());
        //long time0=clock();
        time1=clock();
        for(int iter=0;iter<parallelism;iter++){
            myread();
            if(process_idx>=3*parallelism){
                free(readed[writeidx].first);
                fwrite(to_write[writeidx].first,1,to_write[writeidx].second,fout);
                free(to_write[writeidx].first);
                writeidx++;
            }
        }
        iotime+=clock()-time1;
        printf("clock=%lld\n",clock());
        cudaDeviceSynchronize();
        printf("clock=%lld\n",clock());
        decode<<<cnt,threads_perSM>>>(preading_buf_gpu,pwriting_buf_gpu,pcode_gpu,pcodelen_gpu,p_RawPerThreadGpu);
        printf("clock=%lld\n",clock());
        //if(debug_)
        //    printf("finish_time=%lld\n",clock());
        //sum_time+=clock()-time0;
        //if(streamcnt)
        for(int iii=0;iii<last_cnt;iii++){
            auto tmp_buf=(unsigned char*)malloc(4*1024*1025);
            cudaMemcpyAsync(tmp_buf,whole_writing_buf_gpu[1-cur_s][iii],rawsize[1-cur_s][iii],cudaMemcpyDeviceToHost);
            to_write.push_back(ppi(tmp_buf,rawsize[1-cur_s][iii]));
        }
        printf("clock=%lld\n",clock());
        last_cnt=cnt;
        //CHECK(cudaGetLastError());
        //CHECK(cudaDeviceSynchronize());
        //sum_time_mem+=clock()-time1;
        //for(int iii=0;iii<cnt;iii++){
            //fwrite(,1,fout);

        //}
        streamcnt++;
    }
    int cur_s2=streamcnt&1;
    for(int iii=0;iii<last_cnt;iii++){
        auto tmp_buf=(unsigned char*)malloc(4*1024*1025);
        cudaMemcpyAsync(tmp_buf,whole_writing_buf_gpu[1-cur_s2][iii],rawsize[1-cur_s2][iii],cudaMemcpyDeviceToHost);
        to_write.push_back(ppi(tmp_buf,rawsize[1-cur_s2][iii]));
    }
    CHECK(cudaGetLastError());
    CHECK(cudaDeviceSynchronize());
    sum_time=clock()-time0;
    time1=clock();
    for(int iiii=writeidx;iiii<to_write.size();iiii++){
        fwrite(to_write[iiii].first,1,to_write[iiii].second,fout);
        free(to_write[iiii].first);
    }
    iotime+=clock()-time1;
    printf("sum_time=%lld,iotime=%lld\n",sum_time,iotime);
    //printf("sum_time_including_mem=%lld\n",sum_time_mem);
    fclose(fout);
    fclose(fin);
    /*for(int i=0;i<parallelism;i++){
        free(reading_buf_cpu[i]);
        free(writing_buf_cpu[i]);
        cudaFree((void **)&reading_buf_gpu[i]);
        cudaFree((void **)&writing_buf_gpu[i]);
        cudaFree((void **)&codelen_gpu[i]);
        cudaFree((void **)&code_gpu[i]);
    }
        cudaFree((void **)&p_RawPerThreadGpu);*/
    return 0;
}
/*
*/