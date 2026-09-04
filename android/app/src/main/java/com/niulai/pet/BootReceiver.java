package com.niulai.pet;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;

public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        PetSettings settings = PetSettings.load(context);
        if (!settings.autoStart || !Settings.canDrawOverlays(context)) return;
        Intent service = new Intent(context, PetOverlayService.class).setAction(PetOverlayService.ACTION_START);
        context.startForegroundService(service);
    }
}
