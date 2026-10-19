using System.ComponentModel.DataAnnotations;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using Microsoft.AspNetCore.Mvc;

namespace OmniStream.Api.Controllers;

[ApiController]
[Route("api/clip")]
public sealed class ClipController(
    IConfiguration configuration,
    ILogger<ClipController> logger) : ControllerBase
{
    [HttpPost("trim")]
    [Produces("video/mp4")]
    [ProducesResponseType(typeof(FileStreamResult), StatusCodes.Status200OK, "video/mp4")]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status422UnprocessableEntity)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> Trim(
        [FromBody] TrimClipRequest request,
        CancellationToken cancellationToken)
    {
        if (!double.IsFinite(request.StartTimeSeconds)
            || !double.IsFinite(request.EndTimeSeconds)
            || request.StartTimeSeconds >= request.EndTimeSeconds)
        {
            return BadRequest(new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "Invalid clip time range",
                Detail = "Times must be finite, non-negative values, and the end time must be greater than the start time.",
                Instance = HttpContext.Request.Path
            });
        }

        if (!request.VideoUrl.IsAbsoluteUri
            || (request.VideoUrl.Scheme != Uri.UriSchemeHttp
                && request.VideoUrl.Scheme != Uri.UriSchemeHttps)
            || !string.IsNullOrEmpty(request.VideoUrl.UserInfo))
        {
            return BadRequest(new ProblemDetails
            {
                Status = StatusCodes.Status400BadRequest,
                Title = "Invalid video URL",
                Detail = "The video URL must be an absolute HTTP or HTTPS URL without embedded credentials.",
                Instance = HttpContext.Request.Path
            });
        }

        var outputPath = Path.Combine(Path.GetTempPath(), $"omnistream-clip-{Guid.NewGuid():N}.mp4");
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = string.IsNullOrWhiteSpace(configuration["Ffmpeg:Path"])
                    ? "ffmpeg"
                    : configuration["Ffmpeg:Path"]!,
                UseShellExecute = false,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            var durationSeconds = request.EndTimeSeconds - request.StartTimeSeconds;
            startInfo.ArgumentList.Add("-nostdin");
            startInfo.ArgumentList.Add("-hide_banner");
            startInfo.ArgumentList.Add("-loglevel");
            startInfo.ArgumentList.Add("error");
            startInfo.ArgumentList.Add("-ss");
            startInfo.ArgumentList.Add(request.StartTimeSeconds.ToString("R", CultureInfo.InvariantCulture));
            startInfo.ArgumentList.Add("-i");
            startInfo.ArgumentList.Add(request.VideoUrl.AbsoluteUri);
            startInfo.ArgumentList.Add("-t");
            startInfo.ArgumentList.Add(durationSeconds.ToString("R", CultureInfo.InvariantCulture));
            startInfo.ArgumentList.Add("-vf");
            startInfo.ArgumentList.Add(
                "crop=w='min(iw,ih*9/16)':h='min(ih,iw*16/9)':x='(iw-ow)/2':y='(ih-oh)/2',scale=1080:1920");
            startInfo.ArgumentList.Add("-map");
            startInfo.ArgumentList.Add("0:v:0");
            startInfo.ArgumentList.Add("-map");
            startInfo.ArgumentList.Add("0:a?");
            startInfo.ArgumentList.Add("-c:v");
            startInfo.ArgumentList.Add("libx264");
            startInfo.ArgumentList.Add("-preset");
            startInfo.ArgumentList.Add("veryfast");
            startInfo.ArgumentList.Add("-crf");
            startInfo.ArgumentList.Add("23");
            startInfo.ArgumentList.Add("-pix_fmt");
            startInfo.ArgumentList.Add("yuv420p");
            startInfo.ArgumentList.Add("-c:a");
            startInfo.ArgumentList.Add("aac");
            startInfo.ArgumentList.Add("-movflags");
            startInfo.ArgumentList.Add("+faststart");
            startInfo.ArgumentList.Add(outputPath);

            using var process = new Process { StartInfo = startInfo };
            try
            {
                if (!process.Start())
                {
                    logger.LogError("FFmpeg could not be started.");
                    return FfmpegUnavailable();
                }
            }
            catch (Win32Exception exception)
            {
                logger.LogError(exception, "FFmpeg could not be started.");
                return FfmpegUnavailable();
            }

            var errorOutputTask = process.StandardError.ReadToEndAsync();
            try
            {
                await process.WaitForExitAsync(cancellationToken);
            }
            catch (OperationCanceledException)
            {
                if (!process.HasExited)
                {
                    try
                    {
                        process.Kill(entireProcessTree: true);
                    }
                    catch (InvalidOperationException) when (process.HasExited)
                    {
                    }
                }

                await process.WaitForExitAsync(CancellationToken.None);
                throw;
            }

            _ = await errorOutputTask;
            if (process.ExitCode != 0
                || !System.IO.File.Exists(outputPath)
                || new FileInfo(outputPath).Length == 0)
            {
                logger.LogWarning("FFmpeg failed to trim the video with exit code {ExitCode}.", process.ExitCode);
                return UnprocessableEntity(new ProblemDetails
                {
                    Status = StatusCodes.Status422UnprocessableEntity,
                    Title = "Video could not be trimmed",
                    Detail = "FFmpeg could not process the supplied video and time range.",
                    Instance = HttpContext.Request.Path
                });
            }

            var fileStream = new FileStream(
                outputPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 65536,
                FileOptions.Asynchronous | FileOptions.SequentialScan | FileOptions.DeleteOnClose);
            outputPath = string.Empty;
            return File(fileStream, "video/mp4", "clip.mp4");
        }
        finally
        {
            if (!string.IsNullOrEmpty(outputPath) && System.IO.File.Exists(outputPath))
            {
                System.IO.File.Delete(outputPath);
            }
        }
    }

    private ObjectResult FfmpegUnavailable() =>
        StatusCode(StatusCodes.Status503ServiceUnavailable, new ProblemDetails
        {
            Status = StatusCodes.Status503ServiceUnavailable,
            Title = "Video trimming is unavailable",
            Detail = "The FFmpeg executable is unavailable on the server.",
            Instance = HttpContext.Request.Path
        });
}

/// <summary>Describes a video and the time range to extract as a vertical clip.</summary>
public sealed record TrimClipRequest
{
    /// <summary>Absolute HTTP or HTTPS URL of the source video.</summary>
    [Required]
    public required Uri VideoUrl { get; init; }

    /// <summary>Start time in seconds, inclusive.</summary>
    [Range(0, double.MaxValue)]
    public double StartTimeSeconds { get; init; }

    /// <summary>End time in seconds, exclusive.</summary>
    [Range(0, double.MaxValue)]
    public double EndTimeSeconds { get; init; }
}
