#include<bits/stdc++.h>
using namespace std;
typedef unsigned char u8;
typedef unsigned long long u64;
int cpu_size=0;
u8 read_buf[65536*256+10],gpu_buf[65536*256+10+65536],write_buf[65536*256*8+65536];
u8 codelen[256];
u64 code[256];
int pos_yingshe[65536*256*8+65536];
int duan_end[128];
u8 pianyi[128];
int huanyuan(unsigned char*x){
    return x[0]*65536+x[1]*256+x[2];
}
int main(int argc, char **argv){
    if (argc != 3) 
    {
        printf("usage: %s infile outfile\n", argv[0]);
        exit(1);
    }
    memset(pos_yingshe,-1,sizeof(pos_yingshe));
    FILE *fin=fopen(argv[1],"rb"),*fout=fopen(argv[2],"wb");
    fread(read_buf,1,3,fin);
    cpu_size=huanyuan(read_buf);
    fread(read_buf+3,1,cpu_size-3,fin);
    fclose(fin);
    if(read_buf[3+8]!=0){
        printf("unsupported");
        exit(1);
    }
    int sum_fuhao=0;
    unsigned char*codecount=read_buf+3+8+1;
    for(int k=0;k<8;k++) {
        sum_fuhao+=codecount[k]*(k+1);
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
        pos_yingshe[writing-write_buf]=pos-oldpos;
    }
    int rawsize=writing-write_buf;
    gpu_buf[0]=(rawsize>>24)&255;
    gpu_buf[1]=(rawsize>>16)&255;
    gpu_buf[2]=(rawsize>>8)&255;
    gpu_buf[3]=rawsize&255;
    memcpy(gpu_buf+4,read_buf+3,17);
    memcpy(gpu_buf+4+17,read_buf+20,sum_fuhao);
    int sum;
    if(rawsize>128*256){
        sum=128;
    }
    else{
        sum=(rawsize+255)/256;
    }
    int meiduan_raw=(rawsize+sum-1)/sum;
    gpu_buf[4+17+sum_fuhao]=(meiduan_raw>>16)&255;
    gpu_buf[4+17+sum_fuhao+1]=(meiduan_raw>>8)&255;
    gpu_buf[4+17+sum_fuhao+2]=meiduan_raw&255;
    gpu_buf[4+17+sum_fuhao+3]=sum;
    for(int i=0;i<sum;i++){
        int curend=(i+1)*meiduan_raw;
        if(curend>rawsize)curend=rawsize;
        while(pos_yingshe[curend]==-1)curend++;
        duan_end[i]=pos_yingshe[curend];//yasuohou
        if(i+1<sum){
            pianyi[i+1]=curend-(i+1)*meiduan_raw;//raw
            gpu_buf[4+17+sum_fuhao+3+1+sum*3+i]=pianyi[i+1];
        }

        gpu_buf[4+17+sum_fuhao+3+1+i*3]=(duan_end[i]>>16)&255;
        gpu_buf[4+17+sum_fuhao+3+1+i*3+1]=(duan_end[i]>>8)&255;
        gpu_buf[4+17+sum_fuhao+3+1+i*3+2]=(duan_end[i])&255;
    }
    memcpy(gpu_buf+4+17+sum_fuhao+3+1+4*sum-1,read_buf+oldpos,cpu_size-oldpos);
    fwrite(gpu_buf,1,4+17+sum_fuhao+3+1+4*sum-1+cpu_size-oldpos,fout);
    //fclose(fin);
    fclose(fout);
    fout=fopen("/home/lycegg/wsl_codes/lyc_tst/cpu_jiema_temp","wb");
    fwrite(write_buf,1,rawsize,fout);
    fclose(fout);
    return 0;
}