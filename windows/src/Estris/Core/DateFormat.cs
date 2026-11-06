namespace Estris.Core;

/// General's date and time formats, shared by everything that shows when something happened.
public static class DateFormat
{
    public enum DateStyle { MonthDay, DayMonth, NumericMonthDay, NumericDayMonth }
    public enum TimeStyle { System, TwentyFour, Twelve }

    public static Setting<DateStyle> Date { get; } = SettingsStore.Shared.Get("dateFormat", DateStyle.DayMonth);
    public static Setting<TimeStyle> Time { get; } = SettingsStore.Shared.Get("timeFormat", TimeStyle.System);

    public static string Show(DateTime when)
    {
        var date = when.ToString(Date.Value switch
        {
            DateStyle.MonthDay => "MMM d",
            DateStyle.DayMonth => "d MMM",
            DateStyle.NumericMonthDay => "M/d",
            _ => "d/M",
        }, Loc.Culture);
        return $"{date}, {ShowTime(when)}";
    }

    public static string ShowTime(DateTime when) => when.ToString(Time.Value switch
    {
        TimeStyle.TwentyFour => "HH:mm",
        TimeStyle.Twelve => "h:mm tt",
        _ => System.Globalization.CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern,
    }, Time.Value == TimeStyle.System ? System.Globalization.CultureInfo.CurrentCulture : Loc.Culture);
}
