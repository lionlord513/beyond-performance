// Command-only integration test against the real shipped manager assembly.
// All writes stay in the disposable fixture supplied by test_bmm.py.
using System;
using System.IO;
using System.Linq;
using System.Web.Script.Serialization;
using BeyondModManager;

class BmmRoundtrip {
    static void Check(bool ok, string message) {
        if (!ok) throw new InvalidOperationException(message);
        Console.WriteLine("PASS " + message);
    }
    static void Write(string path, string text) {
        Directory.CreateDirectory(Path.GetDirectoryName(path)); File.WriteAllText(path,text);
    }
    static ModStore Fixture(string root, bool loader) {
        var game=Path.Combine(root,"Game");
        Write(Path.Combine(game,GameInstallation.BinaryRoot,"DriveBeyondHorizons-Win64-Shipping.exe"),"fixture; never execute");
        if(loader) {
            Write(Path.Combine(game,GameInstallation.BinaryRoot,"ue4ss/UE4SS.dll"),"existing loader sentinel");
            Write(Path.Combine(game,GameInstallation.BinaryRoot,"ue4ss/UE4SS-settings.ini"),"existing settings sentinel");
        }
        return new ModStore(game,Path.Combine(root,"ManagerData"),()=>false);
    }
    static void Main(string[] args) {
        var root=args[0]; var standalone=args[1]; var modonly=args[2]; var oldzip=args[3];
        var manifest=new JavaScriptSerializer().Deserialize<PublicUpdateManifest>(File.ReadAllText(args[4]));
        var checksums=File.ReadAllText(args[5]);
        var fresh=Fixture(Path.Combine(root,"fresh"),false);
        var plan=fresh.PreviewZip(standalone);
        Check(plan.Id=="beyondperformance" && plan.Version==manifest.version && plan.Name=="Beyond Performance","package identity and version");
        Check(plan.Dependencies.Length==1 && plan.Dependencies[0]=="UE4SS" && plan.LoadAfter.Length==0,"no dependency or load-order coupling to other mods");
        Check(plan.MissingDependencies.Count==0 && plan.LuaRoots.Count==1,"standalone ZIP supplies its loader and only its own Lua root");
        Check(plan.Files.Any(f=>f.Path.EndsWith("/native/BeyondPerformanceNative.dll")),"native helper included in manager plan");
        var record=fresh.Install(plan);
        Check(record.Enabled && record.Managed && record.ArchiveHash==ModStore.HashFile(standalone),"fresh standalone install and archive ownership");
        var update=record.Update;
        Check(update.Repository=="lionlord513/beyond-performance" && update.ManifestAsset=="bmm-mod.json","independent update source retained");

        var store=Fixture(Path.Combine(root,"existing"),true);
        var mods=Path.Combine(store.GamePath,GameInstallation.ModsRoot);
        var others=new[]{"BeyondApocalypse","BeyondTuning","BeyondDetours","MixTapeMaker","BeyondApocolypseDevMenu"};
        foreach(var name in others) Write(Path.Combine(mods,name,"Scripts/main.lua"),name+" unchanged fixture");
        Write(Path.Combine(mods,"mods.txt"),"; keep this comment\n"+String.Join("\n",others.Select(n=>n+" : 1"))+"\n");
        var protectedFiles=Directory.GetFiles(store.GamePath,"*",SearchOption.AllDirectories)
            .Where(p=>Path.GetFileName(p)!="mods.txt").ToDictionary(p=>p,p=>ModStore.HashFile(p));
        store.Install(store.PreviewZip(oldzip));
        var own=Path.Combine(mods,"BeyondPerformance");
        Write(Path.Combine(own,"settings.ini"),"frame_cap=true\n");
        Write(Path.Combine(own,"settings.ini.bak"),"frame_cap=false\n");
        Write(Path.Combine(own,"benchmark-personal.csv"),"personal capture\n");
        Write(Path.Combine(own,"state/user.txt"),"personal state\n");
        var personal=new[]{"settings.ini","settings.ini.bak","benchmark-personal.csv","state/user.txt"}
            .ToDictionary(p=>p,p=>ModStore.HashFile(Path.Combine(own,p)));
        var upgraded=store.Install(store.PreviewZip(modonly));
        Check(upgraded.Version==manifest.version && upgraded.Update.Repository==update.Repository,"update replaces prior version and retains its own feed");
        Check(!File.Exists(Path.Combine(own,"Scripts/obsolete.lua")),"update removes only obsolete owned code");
        Check(personal.All(p=>ModStore.HashFile(Path.Combine(own,p.Key))==p.Value),"update preserves settings, backup, capture and state");
        Check(protectedFiles.All(p=>File.Exists(p.Key)&&ModStore.HashFile(p.Key)==p.Value),"all sibling mods and existing loader remain byte-identical");
        var list=File.ReadAllText(Path.Combine(mods,"mods.txt"));
        Check(others.All(n=>list.Contains(n+" : 1")) && list.Contains("; keep this comment"),"other mod-list entries and comments retained");
        store.SetEnabled(plan.Id,false);
        Check(!File.Exists(Path.Combine(own,"Scripts/main.lua")),"manager disable removes own active loader entry");
        store.SetEnabled(plan.Id,true);
        Check(File.Exists(Path.Combine(own,"Scripts/main.lua")) && personal.All(p=>ModStore.HashFile(Path.Combine(own,p.Key))==p.Value),"manager enable restores own code and preferences");
        store.Uninstall(plan.Id);
        Check(!File.Exists(Path.Combine(own,"Scripts/main.lua")) && personal.All(p=>ModStore.HashFile(Path.Combine(own,p.Key))==p.Value),"manager uninstall preserves unowned player data");
        store.Install(store.PreviewZip(modonly));
        Check(personal.All(p=>ModStore.HashFile(Path.Combine(own,p.Key))==p.Value),"manager reinstall retains player data");

        var release=new GitHubUpdateRelease { tag_name="v"+manifest.version,name="Beyond Performance "+manifest.version,
            assets=new[]{new GitHubUpdateAsset { id=1,name=manifest.asset,size=manifest.size,
                browser_download_url=manifest.url,state="uploaded",digest="sha256:"+manifest.sha256 }} };
        var candidate=Updates.ResolveCandidate(update,release,manifest,checksums);
        Updates.VerifyFile(standalone,candidate);
        Check(candidate!=null && candidate.Version==manifest.version,"manager validates exact release URL, tag, size and three agreeing digests");
        Check(Updates.NeedsUpdate(candidate,"1.0.0",null) && !Updates.NeedsUpdate(candidate,manifest.version,candidate.Sha256),"older version updates and matching installed version stays current");
        bool rejected=false; var saved=manifest.sha256;
        try { manifest.sha256=new string('0',64); Updates.ResolveCandidate(update,release,manifest,checksums); }
        catch(InvalidDataException) { rejected=true; }
        finally { manifest.sha256=saved; }
        Check(rejected,"manager rejects conflicting release hash");

        if(args.Length>6 && args[6]=="--online") {
            var published=Updates.QueryModUpdateAsync(update,"0.0.0",null).Result;
            Check(published!=null && published.Version==manifest.version,"anonymous GitHub discovery returns published version");
            var file=Updates.DownloadVerified(published,Path.Combine(root,"verified-public.zip")).Result;
            Check(ModStore.HashFile(file)==candidate.Sha256,"anonymous download matches tested release digest");
            var online=Fixture(Path.Combine(root,"online"),false);
            Check(online.Install(online.PreviewZip(file)).Version==manifest.version,"verified public download installs through actual manager");
        }
        Console.WriteLine("BMM_ROUNDTRIP_PASS");
    }
}
