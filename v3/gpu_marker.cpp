#include<bits/stdc++.h>
#include <sys/stat.h>
using namespace std;
typedef unsigned char u8;
typedef unsigned long long u64;
int cpu_size=0;
u8 read_buf[65536*256+10],gpu_buf[65536*256+10+65536],write_buf[65536*256*8+65536];
u8 codelen[256];
u64 code[256];
int pos_mapping[65536*256*8+65536];
int block_end[128];
u8 offset[128];
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

int DESERIALIZE(unsigned char*x){
    return x[0]*65536+x[1]*256+x[2];
}
int main(int argc, char **argv){
    if (argc != 5) 
    {
        printf("usage: %s infile outfile parallelism debug\nparallelism:thread num per SM\n", argv[0]);
        exit(1);
    }
    int parallelism=stoi(argv[3]);
    int debug_=stoi(argv[4]);
    FILE *fin=fopen(argv[1],"rb"),*fout=fopen(argv[2],"wb");
    FILE *fout2;
    if(debug_)fout2=fopen("/home/lycegg/wsl_codes/lyc_tst/cpu_jiema_temp","wb");
    while(!is_end_of_file(fin)){
        memset(pos_mapping,-1,sizeof(pos_mapping));
        fread(read_buf,1,3,fin);
        cpu_size=DESERIALIZE(read_buf);
        fread(read_buf+3,1,cpu_size-3,fin);
        if(read_buf[3+8]!=0){
            printf("unsupported");
            exit(1);
        }
        int sum_symbol=0;
        unsigned char*codecount=read_buf+3+8+1;
        for(int k=0;k<8;k++) {
            sum_symbol+=codecount[k]*(k+1);
        }
        int i=0;
        int pos=3+8+1+8;
        for(int kk=0;kk<8;kk++) {
            int k=(kk+1)%8;
            for(int j=0;j<codecount[k];j++){
                codelen[i]=k+1;
                memcpy(code+i,read_buf+pos,k+1);
                pos+=k+1;
                i++;
            }
        }
        i=0;
        u8*writing=write_buf;
        int oldpos=pos;
        while(pos<cpu_size){
            if(read_buf[pos]!=255){
                memcpy(writing,&(code[read_buf[pos]]),codelen[read_buf[pos]]);
                writing+=codelen[read_buf[pos]];
            }
            else{
                pos++;
                *writing=read_buf[pos];
                writing++;
            }
            pos++;
            pos_mapping[writing-write_buf]=pos-oldpos;
        }
        int rawsize=writing-write_buf;
        gpu_buf[0]=(rawsize>>24)&255;
        gpu_buf[1]=(rawsize>>16)&255;
        gpu_buf[2]=(rawsize>>8)&255;
        gpu_buf[3]=rawsize&255;
        memcpy(gpu_buf+4,read_buf+3,17);
        memcpy(gpu_buf+4+17,read_buf+20,sum_symbol);
        int sum;
        if(rawsize>parallelism*1024){
            sum=parallelism;
        }
        else{
            sum=(rawsize+1023)/1024;
        }
        int RawPerThread=(rawsize+sum-1)/sum;
        gpu_buf[4+17+sum_symbol]=(RawPerThread>>16)&255;
        gpu_buf[4+17+sum_symbol+1]=(RawPerThread>>8)&255;
        gpu_buf[4+17+sum_symbol+2]=RawPerThread&255;
        gpu_buf[4+17+sum_symbol+3]=sum;
        for(int i=0;i<sum;i++){
            int curend=(i+1)*RawPerThread;
            if(curend>rawsize)curend=rawsize;
            while(pos_mapping[curend]==-1)curend++;
            block_end[i]=pos_mapping[curend];//yasuohou
            if(debug_)
            printf("duan%d:%d->%d\n",curend,pos_mapping[curend],i);
            if(i+1<sum){
                offset[i+1]=curend-(i+1)*RawPerThread;//raw
                if(debug_)
                printf("offset=%d\n",(int)offset[i+1]);
                gpu_buf[4+17+sum_symbol+3+1+sum*3+i]=offset[i+1];
            }

            gpu_buf[4+17+sum_symbol+3+1+i*3]=(block_end[i]>>16)&255;
            gpu_buf[4+17+sum_symbol+3+1+i*3+1]=(block_end[i]>>8)&255;
            gpu_buf[4+17+sum_symbol+3+1+i*3+2]=(block_end[i])&255;
        }
        memcpy(gpu_buf+4+17+sum_symbol+3+1+4*sum-1,read_buf+oldpos,cpu_size-oldpos);
        fwrite(gpu_buf,1,4+17+sum_symbol+3+1+4*sum-1+cpu_size-oldpos,fout);
        if(debug_){
            printf("%d->%d,divided%d\n",rawsize,cpu_size-oldpos,sum);
            fwrite(write_buf,1,rawsize,fout2);
        }
    }
    //fclose(fin);
    fclose(fin);
    fclose(fout);
    if(debug_)fclose(fout2);
    return 0;
}