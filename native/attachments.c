/* Beyond Performance. Reversible Kismet common-subexpression elimination.
 * No Lua ABI imports, injection, executable patches, worker threads or hooks.
 * package.loadlib calls these exports synchronously on the game thread.
 * The file mailbox pattern is reused independently from the user's file bridges.
 */
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include "attachment_guard.h"

static HMODULE module;
static wchar_t root[32768];
static uintptr_t owned_function,owned_script;
static uintptr_t symbols[BP_SYMBOL_COUNT];
static unsigned char original[BP_CODE_SIZE],patched[BP_CODE_SIZE];
static DWORD game_thread;
static int active;
struct Patch {unsigned short offset,destination;};
static const struct Patch patches[]={{0xd8,0x102},{0x12e,0x158},{0x1f7,0x224}};

static void init(void){
 if(root[0])return;
 GetModuleFileNameW(module,root,32768);
 wchar_t *p=wcsrchr(root,L'\\');if(p)*p=0;
 p=wcsrchr(root,L'\\');if(p)*p=0;
 wchar_t state[32768];swprintf(state,32768,L"%ls\\state",root);CreateDirectoryW(state,0);
}
static void status(const char *kind,const char *message){
 init();wchar_t path[32768];swprintf(path,32768,L"%ls\\state\\attachment-status.txt",root);
 FILE *f=_wfopen(path,L"wb");if(f){fprintf(f,"%s\n%s\n",kind,message);fclose(f);}
}
static int read_mem(uintptr_t address,void *out,size_t count){SIZE_T n=0;return address&&ReadProcessMemory(GetCurrentProcess(),(void*)address,out,count,&n)&&n==count;}
static int write_mem(uintptr_t address,const void *data,size_t count){SIZE_T n=0;return WriteProcessMemory(GetCurrentProcess(),(void*)address,data,count,&n)&&n==count;}
static int script_of(uintptr_t function,uintptr_t *script){
 struct {uintptr_t data;int32_t size,capacity;} a;
 if(!read_mem(function+0x60,&a,sizeof(a))||a.size!=BP_CODE_SIZE||a.capacity<a.size||a.capacity>65536||!a.data)return 0;
 *script=a.data;return 1;
}
static int validate(const unsigned char *code,const uintptr_t *values){
 for(size_t i=0;i<BP_CODE_SIZE;i++)if((code[i]&mask[i])!=expected[i])return 0;
 for(size_t i=0;i<sizeof(refs)/sizeof(refs[0]);i++){
  const struct Reference *r=&refs[i];uintptr_t value=values[r->index];
  if(r->width==8){uintptr_t actual;memcpy(&actual,code+r->offset,8);if(actual!=value)return 0;}
  else {
   uint32_t name[2],actual[3];
   if(!value||!read_mem(value+24,name,8)||name[1]!=0)return 0;
   memcpy(actual,code+r->offset,12);
   if(actual[0]!=name[0]||actual[1]!=0||actual[2]!=0)return 0;
  }
 }
 /* Same owner-result variable and exact same call to the pure parent lookup. */
 if(memcmp(code+0x3b,code+0xd8,0x2a)||memcmp(code+0x3b,code+0x12e,0x2a))return 0;
 if(memcmp(code+0x1a3,code+0x1f7,0x2d))return 0;
 return 1;
}
static int owned_current(unsigned char *now){
 uintptr_t script;
 return active&&script_of(owned_function,&script)&&script==owned_script&&read_mem(script,now,BP_CODE_SIZE);
}
static int restore(void){
 if(!active)return 1;
 unsigned char now[BP_CODE_SIZE];
 if(!owned_current(now)) {status("CONFLICT","Original function no longer available; no memory was changed. Restart resets transient changes.");return 0;}
 for(size_t i=0;i<sizeof(patches)/sizeof(patches[0]);i++){
  size_t off=patches[i].offset;
  if(memcmp(now+off,patched+off,5)){status("CONFLICT","Another patch changed the owned instructions; restoration refused.");return 0;}
 }
 /* Restore only our three instructions, preserving all unrelated code. */
 for(size_t i=0;i<sizeof(patches)/sizeof(patches[0]);i++){
  size_t off=patches[i].offset;if(!write_mem(owned_script+off,original+off,5)){status("ERROR","Could not restore owned instructions.");return 0;}
 }
 active=0;owned_script=owned_function=0;return 1;
}
__declspec(dllexport) int bp_attachment_apply(void *lua){
 (void)lua;init();
 if(game_thread&&game_thread!=GetCurrentThreadId()){status("ERROR","Apply must run on the same game thread.");return 0;}
 game_thread=GetCurrentThreadId();
 if(active){unsigned char now[BP_CODE_SIZE];if(owned_current(now)&&!memcmp(now,patched,BP_CODE_SIZE)){status("ON","Duplicate parent traversal removed; attachment timing unchanged.");return 0;}status("CONFLICT","Active function changed externally; no additional patch applied.");return 0;}
 wchar_t path[32768];swprintf(path,32768,L"%ls\\state\\attachment-request.txt",root);
 FILE *f=_wfopen(path,L"rb");if(!f){status("ERROR","Missing reflected-symbol request.");return 0;}
 char magic[32]={0};unsigned long long address=0;uintptr_t values[BP_SYMBOL_COUNT];
 int good=fscanf(f,"%31s",magic)==1&&!strcmp(magic,"BP_ATTACH_1")&&fscanf(f,"%llu",&address)==1;
 for(size_t i=0;i<BP_SYMBOL_COUNT&&good;i++){unsigned long long v;good=fscanf(f,"%llu",&v)==1;values[i]=(uintptr_t)v;}
 fclose(f);if(!good){status("ERROR","Invalid reflected-symbol request.");return 0;}
 uintptr_t script;unsigned char code[BP_CODE_SIZE];
 if(!script_of((uintptr_t)address,&script)||!read_mem(script,code,sizeof(code))||!validate(code,values)){status("UNSUPPORTED","Game function differs from the verified semantic signature; left unchanged.");return 0;}
 memcpy(original,code,sizeof(code));memcpy(patched,code,sizeof(code));memcpy(symbols,values,sizeof(values));
 for(size_t i=0;i<sizeof(patches)/sizeof(patches[0]);i++){
  size_t off=patches[i].offset;uint32_t target=patches[i].destination;
  patched[off]=0x06;memcpy(patched+off+1,&target,4);
 }
 owned_function=(uintptr_t)address;owned_script=script;active=1;
 for(size_t i=0;i<sizeof(patches)/sizeof(patches[0]);i++){
  size_t off=patches[i].offset;
  if(!write_mem(script+off,patched+off,5)){
   /* Writes to these already-readable heap bytes normally cannot fail. Roll
    * back only successfully written regions; never overwrite foreign bytes. */
   unsigned char now[5];
   for(size_t j=0;j<=i;j++){size_t k=patches[j].offset;if(read_mem(script+k,now,5)&&!memcmp(now,patched+k,5))write_mem(script+k,original+k,5);}
   active=0;status("ERROR","Patch write failed; completed writes rolled back.");return 0;
  }
 }
 status("ON","Duplicate parent traversal removed; attachment timing unchanged.");return 0;
}
__declspec(dllexport) int bp_attachment_restore(void *lua){
 (void)lua;if(game_thread&&game_thread!=GetCurrentThreadId()){status("ERROR","Restore must run on the game thread.");return 0;}
 if(restore())status("OFF","Original attachment lookup restored.");return 0;
}
__declspec(dllexport) int bp_attachment_status(void *lua){
 (void)lua;if(!active){status("OFF","Original attachment lookup is active.");return 0;}
 unsigned char now[BP_CODE_SIZE];
 if(owned_current(now)&&!memcmp(now,patched,BP_CODE_SIZE))status("ON","Duplicate parent traversal removed; attachment timing unchanged.");
 else status("CONFLICT","Function changed externally; no memory was changed by this check.");return 0;
}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID reserved){
 (void)reserved;if(reason==DLL_PROCESS_ATTACH){module=h;DisableThreadLibraryCalls(h);}return TRUE;
}
