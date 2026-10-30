import android.content.Context;
import android.content.pm.*;
import android.os.Looper;
import java.security.MessageDigest;
public class SignatureProbe {
  static void info(String label, PackageInfo p) throws Exception {
    if (p == null) { System.out.println(label+" null"); return; }
    Signature[] now=p.signingInfo==null?null:p.signingInfo.getApkContentsSigners();
    System.out.println(label+" code="+p.getLongVersionCode()+" signingInfo="+(p.signingInfo!=null)+" current="+(now==null?-1:now.length)+" legacy="+(p.signatures==null?-1:p.signatures.length));
    if(now!=null)for(Signature s:now)System.out.println(label+" currentHash="+hex(MessageDigest.getInstance("SHA-256").digest(s.toByteArray())));
    if(p.signatures!=null)for(Signature s:p.signatures)System.out.println(label+" legacyHash="+hex(MessageDigest.getInstance("SHA-256").digest(s.toByteArray())));
  }
  static String hex(byte[] a){StringBuilder s=new StringBuilder();for(byte b:a)s.append(String.format("%02x",b));return s.toString();}
    static java.util.Set<String> hashes(PackageInfo p)throws Exception{
    java.util.Set<String> result=new java.util.HashSet<>();
    if(p!=null && p.signingInfo!=null)for(Signature s:p.signingInfo.getApkContentsSigners())
      result.add(hex(MessageDigest.getInstance("SHA-256").digest(s.toByteArray())));
    return result;
  }
  public static void main(String[] a)throws Exception{
    Looper.prepareMainLooper();
    Class<?> t=Class.forName("android.app.ActivityThread");
    Object th=t.getMethod("systemMain").invoke(null);
    Context c=(Context)t.getMethod("getSystemContext").invoke(th);
    PackageManager pm=c.getPackageManager();
    for(int f:new int[]{0x08000000,0x08000040,0x40}){
      info("installed flags="+f,pm.getPackageInfo("com.fenghaha.kazumitv",f));
            PackageInfo archive=pm.getPackageArchiveInfo(a[0],f);
      info("archive flags="+f,archive);
      if(f==0x08000040){
        PackageInfo installed=pm.getPackageInfo("com.fenghaha.kazumitv",f);
        java.util.Set<String> current=hashes(installed), candidate=hashes(archive);
        boolean match=!current.isEmpty() && current.equals(candidate);
        boolean expected=a.length<2 || !a[1].equals("mismatch");
        if(match!=expected)throw new AssertionError("current signer check did not produce expected result");
        System.out.println("Combined flags exact current signer check PASS, match="+match);
      }
    }
  }
}