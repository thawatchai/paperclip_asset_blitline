paperclip_asset_blitline
========================

Installation:
-------------

In your Gemfile:

```gem 'paperclip_asset_blitline'```

Follow the instructions in [http://www.blitline.com/docs/s3_permissions](http://www.blitline.com/docs/s3_permissions) to set S3 permission.


Necessary ENV settings:
-----------------------

ENV["BLITLINE_APPLICATION_ID"] = your blitline application id.
ENV["S3_BUCKET"] = your S3 bucket name.
ENV["S3_ACCESS_KEY_ID"] = your S3 access key id.


Usage:
------

in your models that contain ```has_attached_file <asset_name>```:

```include PaperclipAssetBlitline::Hook```

and below the ```has_attached_file <asset_name>```:

```blitline_asset_attributes <asset_name```