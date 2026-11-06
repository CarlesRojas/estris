using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Velopack;

namespace Estris;

/// Starts the app. Velopack goes first, since it may be running an install or update step,
/// and a second copy only tells the first to open Settings.
public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        VelopackApp.Build().Run();
        if (!Core.SingleInstance.TryBecomeFirst())
        {
            Core.SingleInstance.AskFirstToOpenSettings();
            return;
        }

        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(_ =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            new App(openedAtLogin: args.Contains(Core.LoginItem.Argument));
        });
    }
}
