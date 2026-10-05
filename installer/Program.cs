using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows.Forms;
[assembly: System.Reflection.AssemblyVersion("0.2.0.0")]
namespace SlowDamageRussian {
class MainForm:Form {
    TextBox folder=new TextBox(),log=new TextBox();Button browse=new Button(),install=new Button(),remove=new Button();
    public MainForm(){
        Text="Slow Damage — русский перевод v0.2.0";ClientSize=new Size(690,440);MinimumSize=Size;StartPosition=FormStartPosition.CenterScreen;Font=new Font("Segoe UI",10);
        Controls.Add(new Label{Text="SLOW DAMAGE / русский перевод",Location=new Point(22,20),AutoSize=true,Font=new Font("Segoe UI",18,FontStyle.Bold)});
        Controls.Add(new Label{Text="JAST USA 1.10 — установка сразу на чистую игру",Location=new Point(24,65),AutoSize=true});
        Controls.Add(new Label{Text="Выберите папку, в которой находится slow_damage_en.exe",Location=new Point(24,97),AutoSize=true});
        folder.SetBounds(24,128,540,30);browse.SetBounds(574,127,90,32);browse.Text="Обзор…";
        install.SetBounds(24,180,145,36);install.Text="Установить";remove.SetBounds(184,180,210,36);remove.Text="Удалить русификатор";
        log.SetBounds(24,236,640,170);log.Multiline=true;log.ReadOnly=true;log.ScrollBars=ScrollBars.Vertical;log.BackColor=Color.White;
        Controls.AddRange(new Control[]{folder,browse,install,remove,log});
        if(File.Exists(@"D:\Slow Damage\slow_damage_en.exe"))folder.Text=@"D:\Slow Damage";
        browse.Click+=delegate{using(var d=new FolderBrowserDialog()){d.Description="Папка Slow Damage";d.SelectedPath=folder.Text;if(d.ShowDialog(this)==DialogResult.OK)folder.Text=d.SelectedPath;}};
        install.Click+=delegate{Run("Install");};remove.Click+=delegate{Run("Uninstall");};
        log.Text="Установщик проверяет архивы и создаёт резервные копии.\r\nСохранения игры остаются на месте.\r\n";
    }
    void Run(string action){
        var path=folder.Text.Trim();if(!File.Exists(Path.Combine(path,"slow_damage_en.exe"))){MessageBox.Show(this,"Выберите папку с slow_damage_en.exe.");return;}
        folder.Enabled=browse.Enabled=install.Enabled=remove.Enabled=false;
        new Thread(delegate(){int code;string output;try{output=Program.Execute(action,path,out code);}catch(Exception e){output=e.Message;code=1;}
            Invoke((MethodInvoker)delegate{log.AppendText(output+"\r\n");folder.Enabled=browse.Enabled=install.Enabled=remove.Enabled=true;if(code!=0)MessageBox.Show(this,"Операция остановлена. Подробности в журнале.");});}){IsBackground=true}.Start();
    }
}
static class Program {
    static string Quote(string value){if(value.Contains("\"")||value.Contains("\r")||value.Contains("\n"))throw new ArgumentException("Недопустимый путь");return "\""+value.TrimEnd('\\')+"\"";}
    internal static string Execute(string action,string game,out int code){
        string script=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"install.ps1");
        var info=new ProcessStartInfo("powershell.exe","-NoProfile -ExecutionPolicy Bypass -File "+Quote(script)+" -Action "+action+" -GamePath "+Quote(game));
        info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;
        info.StandardOutputEncoding=Encoding.UTF8;info.StandardErrorEncoding=Encoding.UTF8;
        using(var p=Process.Start(info)){string error="";var thread=new Thread(delegate(){error=p.StandardError.ReadToEnd();});thread.Start();string output=p.StandardOutput.ReadToEnd();p.WaitForExit();thread.Join();code=p.ExitCode;return output+error;}
    }
    [STAThread]static void Main(string[] args){
        if(args.Length==2&&(args[0]=="--install"||args[0]=="--uninstall")){int code;try{string text=Execute(args[0]=="--install"?"Install":"Uninstall",args[1],out code);File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"operation.log"),text,Encoding.UTF8);Environment.ExitCode=code;}catch{Environment.ExitCode=1;}return;}
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new MainForm());
    }
}}
