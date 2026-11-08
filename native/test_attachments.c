/* Meaningful in-process tests of signature guards and reversible ownership.
 * Uses only synthetic fixture memory, never a game process. */
#include "attachments.c"
#include <stdlib.h>
static int checks;
#define CHECK(x) do {checks++;if(!(x)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);return 1;}}while(0)
int main(int argc,char **argv){
 if(argc!=2){fprintf(stderr,"Expected isolated fixture directory\n");return 2;}
 MultiByteToWideChar(CP_UTF8,0,argv[1],-1,root,32768);CreateDirectoryW(root,0);
 wchar_t state[32768];swprintf(state,32768,L"%ls\\state",root);CreateDirectoryW(state,0);
 unsigned char code[BP_CODE_SIZE],saved[BP_CODE_SIZE],objects[BP_SYMBOL_COUNT][160];
 uintptr_t values[BP_SYMBOL_COUNT];memset(objects,0,sizeof(objects));memcpy(code,expected,sizeof(code));
 for(size_t i=0;i<BP_SYMBOL_COUNT;i++){values[i]=(uintptr_t)objects[i];uint32_t name=100+(uint32_t)i;memcpy(objects[i]+24,&name,4);}
 for(size_t i=0;i<sizeof(refs)/sizeof(refs[0]);i++){
  const struct Reference *r=&refs[i];
  if(r->width==8)memcpy(code+r->offset,&values[r->index],8);
  else {memcpy(code+r->offset,objects[r->index]+24,4);memset(code+r->offset+4,0,8);}
 }
 CHECK(validate(code,values));
 code[0]^=1;CHECK(!validate(code,values));code[0]^=1;
 code[refs[0].offset]^=1;CHECK(!validate(code,values));code[refs[0].offset]^=1;
 memcpy(saved,code,sizeof(code));
 unsigned char function[256]={0};uintptr_t script=(uintptr_t)code;int size=BP_CODE_SIZE;memcpy(function+0x60,&script,8);memcpy(function+0x68,&size,4);memcpy(function+0x6c,&size,4);
 wchar_t request[32768];swprintf(request,32768,L"%ls\\state\\attachment-request.txt",root);FILE *f=_wfopen(request,L"wb");CHECK(f!=NULL);fprintf(f,"BP_ATTACH_1\n%llu\n",(unsigned long long)(uintptr_t)function);for(size_t i=0;i<BP_SYMBOL_COUNT;i++)fprintf(f,"%llu\n",(unsigned long long)values[i]);fclose(f);
 bp_attachment_apply(0);CHECK(active);CHECK(code[0xd8]==0x06&&code[0x12e]==0x06&&code[0x1f7]==0x06);
 bp_attachment_apply(0);CHECK(active);CHECK(!memcmp(code,patched,sizeof(code)));
 bp_attachment_restore(0);CHECK(!active);CHECK(!memcmp(code,saved,sizeof(code)));
 bp_attachment_apply(0);CHECK(active);code[0x1f7]=0x0b;
 bp_attachment_restore(0);CHECK(active);CHECK(code[0x1f7]==0x0b); /* never clobber foreign instruction */
 memcpy(code+0x1f7,patched+0x1f7,5);code[0x2c0]=0x0b;
 bp_attachment_restore(0);CHECK(!active);CHECK(code[0x2c0]==0x0b); /* preserve unrelated foreign edit */
 code[0x2c0]=saved[0x2c0];CHECK(!memcmp(code,saved,sizeof(code)));
 code[1]^=1;bp_attachment_apply(0);CHECK(!active);code[1]^=1;
 memset(function+0x60,0,8);bp_attachment_apply(0);CHECK(!active);
 fprintf(stdout,"PASS %d native guard/restore checks\n",checks);return 0;
}
